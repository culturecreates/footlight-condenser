class MonitoringIssue < ApplicationRecord
  scope :open_issues, -> { where(resolved_at: nil) }

  def self.fingerprint_for(statement)
    Digest::SHA256.hexdigest("#{statement.webpage_id}:#{statement.source_id}")
  end
end
