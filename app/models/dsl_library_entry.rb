class DslLibraryEntry < ApplicationRecord
  has_many :versions, class_name: "DslLibraryVersion", dependent: :restrict_with_error
  before_validation { self.name = name.to_s.strip.upcase }
  validates :name, presence: true, uniqueness: true, format: { with: /\A[A-Z][A-Z0-9_]*\z/ }, exclusion: { in: ["SELF_URL"] }
  validates :body, presence: true, length: { maximum: 100_000 }
  validate :stable_name
  validate :valid_expansion
  before_update { self.revision += 1 if will_save_change_to_body? }
  after_save do
    versions.create!(revision: revision, body: body) if saved_change_to_body? || versions.empty?
  end

  def references
    Source.where("algorithm_value LIKE ?", "%#{Source.sanitize_sql_like("$$#{name}$$")}%")
  end

  def library_references
    DslLibraryEntry.where.not(id: id).where("body LIKE ?", "%#{self.class.sanitize_sql_like("$$#{name}$$")}%")
  end

  private

  def stable_name
    errors.add(:name, "is a stable identifier; create a new entry to use another name") if persisted? && will_save_change_to_name?
  end

  def valid_expansion
    return if name.blank? || body.blank? || name == "SELF_URL"
    parts = body.split(';').map(&:strip).reject(&:empty?)
    unless parts.all? { |step| step.match?(Dsl::LibraryExpander::TOKEN) || step.match?(/\A[a-z_]+=/) }
      errors.add(:body, "must contain complete DSL steps or standalone library tokens")
      return
    end
    Dsl::LibraryExpander.call("$$#{name}$$", overrides: {name => {name: name, body: body, revision: revision}})
  rescue Dsl::LibraryExpander::Error => error
    errors.add(:body, error.message)
  end
end
