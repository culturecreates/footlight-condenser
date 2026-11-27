class MonitoringIssue < ApplicationRecord
  scope :open_issues, -> { where(resolved_at: nil) }

  def category_label
    case kind
    when "dsl_error" then "DSL error"
    when "resource_list_refresh" then "ResourceList refresh"
    when "resource_list_import_incomplete" then "ResourceList import incomplete"
    when "possible_missed_event" then "Possible missed upcoming event"
    else kind.humanize
    end
  end

  def self.fingerprint_for(statement)
    Digest::SHA256.hexdigest("#{statement.webpage_id}:#{statement.source_id}")
  end
end
