class PreprocessingPolicy < ApplicationRecord
  has_many :runs, class_name: "PreprocessingRun", dependent: :restrict_with_error
  scope :enabled_policies, -> { where(enabled: true) }
  attr_accessor :expected_seedurl
  before_validation :capture_identity, on: :create
  validates :statement_id, uniqueness: true
  validates :statement_id, :website_id, :webpage_id, :source_id, :seedurl, presence: true
  validates :interval_hours, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 168 }
  validates :stale_after_hours, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 720 }
  validate :validate_configuration

  def target
    Statement.includes(:source, webpage: :website).find_by(id: statement_id)
  end

  def identity_error(statement = target)
    return "Target statement ##{statement_id} no longer exists" unless statement
    return "Target identity changed; inspect policy before refreshing" unless
      statement.source_id == source_id && statement.webpage_id == webpage_id &&
      statement.source.website_id == website_id && statement.webpage.website_id == website_id &&
      statement.webpage.website.seedurl == seedurl
    nil
  end

  def configuration_digest
    Digest::SHA256.hexdigest([statement_id, website_id, webpage_id, source_id, seedurl,
      enabled, inputs_verified, interval_hours, stale_after_hours, input_statement_ids].to_json)
  end

  def monitoring_issues
    scope = MonitoringIssue.open_issues
    scope.where(preprocessing_policy_id: id).or(scope.where(fingerprint: MonitoringIssue.fingerprint_for(self)))
  end

  def input_observations
    records = Statement.includes(:source, webpage: :website).where(id: input_statement_ids).index_by(&:id)
    input_statement_ids.map do |id|
      statement = records[id]
      { id: id, refreshed_at: statement&.cache_refreshed&.iso8601(6),
        valid_identity: !!(statement && statement.source.website_id == website_id && statement.webpage.website_id == website_id),
        seedurl: statement&.webpage&.website&.seedurl }
    end
  end

  private

  def capture_identity
    statement = target
    return errors.add(:statement_id, "does not exist in this environment") unless statement
    self.website_id = statement.webpage.website_id
    self.webpage_id = statement.webpage_id
    self.source_id = statement.source_id
    self.seedurl = statement.webpage.website.seedurl
  end

  def validate_configuration
    fields = %w[statement_id website_id webpage_id source_id seedurl enabled inputs_verified interval_hours stale_after_hours input_statement_ids]
    return unless new_record? || (changed_attribute_names_to_save & fields).any?
    if new_record? && (expected_seedurl.blank? || expected_seedurl != seedurl)
      errors.add(:base, "Expected website seedurl must match the target statement")
    end
    if stale_after_hours && interval_hours && stale_after_hours < interval_hours
      errors.add(:stale_after_hours, "must be at least the refresh interval")
    end
    valid_ids = input_statement_ids.is_a?(Array) && input_statement_ids.all? { |id| id.is_a?(Integer) && id.positive? } &&
      input_statement_ids.uniq.size == input_statement_ids.size && !input_statement_ids.include?(statement_id)
    errors.add(:input_statement_ids, "must contain unique positive IDs other than the target") unless valid_ids
    return unless enabled?
    errors.add(:inputs_verified, "must be confirmed after inspecting this environment's DSL inputs") unless inputs_verified?
    errors.add(:base, identity_error) if identity_error
    unless Webpage.joins(:rdfs_class).where(website_id: website_id, rdfs_classes: { name: "ResourceList" }).exists?
      errors.add(:base, "Target website must contain ResourceList webpages")
    end
    if !valid_ids || input_statement_ids.empty?
      errors.add(:input_statement_ids, "must identify the required upstream statements before enabling")
    elsif input_observations.any? { |item| !item[:valid_identity] }
      errors.add(:input_statement_ids, "must exist in the same preprocessing website")
    end
  end
end
