class DslLibraryEntry < ApplicationRecord
  has_many :versions, class_name: "DslLibraryVersion", dependent: :restrict_with_error
  before_validation do
    self.name = name.to_s.strip.upcase
    self.aliases = (Array(aliases) + [name_in_database]).compact.uniq - [name] if persisted? && will_save_change_to_name?
  end
  validates :name, presence: true, uniqueness: true, format: { with: /\A[A-Z][A-Z0-9_]*\z/ }, exclusion: { in: ["SELF_URL"] }
  validates :body, presence: true, length: { maximum: 100_000 }
  validate :available_name
  validate :valid_expansion
  before_update { self.revision += 1 if will_save_change_to_body? || will_save_change_to_name? }
  around_update :rewrite_renamed_references
  after_save do
    versions.create!(revision: revision, name: name, body: body) if saved_change_to_body? || saved_change_to_name? || versions.empty?
  end

  def references
    names = [name] + Array(aliases)
    names.map { |value| Source.where("algorithm_value LIKE ?", "%#{Source.sanitize_sql_like("$$#{value}$$")}%") }.reduce { |scope, other| scope.or(other) }
  end

  def library_references
    names = [name] + Array(aliases)
    names.map { |value| library_references_for("$$#{value}$$") }.reduce { |scope, other| scope.or(other) }
  end

  private

  def available_name
    if self.class.where.not(id: id).where("aliases ? :name", name: name).exists?
      errors.add(:name, "is a previous name of another instruction")
    end
  end

  def rewrite_renamed_references
    old_name = name_in_database
    changed = will_save_change_to_name?
    yield
    return unless changed

    token = "$$#{old_name}$$"
    Source.where("algorithm_value LIKE ?", "%#{Source.sanitize_sql_like(token)}%").order(:id).find_each do |source|
      source.with_lock do
        rewritten = self.class.rename_steps(source.algorithm_value, old_name, name)
        source.update!(algorithm_value: rewritten) if rewritten != source.algorithm_value
      end
    end
    library_references_for(token).each do |entry|
      entry.with_lock do
        rewritten = self.class.rename_steps(entry.body, old_name, name)
        entry.update!(body: rewritten) if rewritten != entry.body
      end
    end
  rescue ActiveRecord::RecordInvalid
    errors.add(:base, "No changes saved: a referencing source or library entry could not be updated")
    raise
  end

  def library_references_for(token)
    self.class.where.not(id: id).where("body LIKE ?", "%#{self.class.sanitize_sql_like(token)}%").order(:id)
  end

  public

  def self.shorten_array_names!
    transaction do
      order(:id).lock.to_a.select { |entry| entry.name.start_with?("ARRAY_") }.map do |entry|
        old_name = entry.name
        new_name = case old_name
        when "ARRAY_FIRST" then "A_DROP_FIRST"
        when "ARRAY_DROP_FIRST" then "A_DROP_FIRST_ALWAYS"
        else old_name.sub(/\AARRAY_/, "A_")
        end
        # Earlier renames may have rewritten this entry's body and lock version.
        entry.reload.update!(name: new_name)
        { id: entry.id, from: old_name, to: new_name }
      end
    end
  end

  def self.rename_steps(algorithm, old_name, new_name)
    pattern = /\A(\s*)#{Regexp.escape("$$#{old_name}$$")}(\s*)\z/
    algorithm.to_s.split(';', -1).map { |step| step.sub(pattern) { "#{Regexp.last_match(1)}$$#{new_name}$$#{Regexp.last_match(2)}" } }.join(';')
  end

  private

  def valid_expansion
    return if name.blank? || body.blank? || name == "SELF_URL"
    parts = body.split(';').map(&:strip).reject(&:empty?)
    unless parts.all? { |step| step.match?(Dsl::LibraryExpander::TOKEN) || step.match?(/\A[a-z_]+=/) }
      errors.add(:body, "must contain complete DSL steps or standalone library tokens")
      return
    end
    snapshot = {name: name, body: body, revision: revision}
    overrides = ([name] + Array(aliases)).index_with { snapshot }
    Dsl::LibraryExpander.call("$$#{name}$$", overrides: overrides)
  rescue Dsl::LibraryExpander::Error => error
    errors.add(:body, error.message)
  end
end
