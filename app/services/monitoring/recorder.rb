module Monitoring
  # Only actual statement refreshes call this service. Comparisons and replays
  # remain read-only and never create or resolve operational issues.
  class Recorder
    def self.failure(statement, payload)
      return unless payload.is_a?(Hash) && payload.with_indifferent_access[:notify] == "daily"

      safely do
        now = Time.current
        message = payload.with_indifferent_access[:error].to_s.encode("UTF-8", invalid: :replace, undef: :replace).squish.first(1000)
        issue = MonitoringIssue.create_or_find_by!(fingerprint: MonitoringIssue.fingerprint_for(statement)) do |record|
          record.seedurl = statement.webpage.website.seedurl
          record.source_id = statement.source_id
          record.message = message
          record.first_seen_at = now
          record.last_seen_at = now
          record.occurrences = 0
        end
        issue.with_lock do
          issue.update!(seedurl: statement.webpage.website.seedurl, website_name: statement.webpage.website.name,
            url: statement.webpage.url, source_id: statement.source_id, statement_id: statement.id,
            property_name: statement.source.property.label, message: message,
            first_seen_at: issue.resolved_at? ? now : issue.first_seen_at,
            last_seen_at: now, occurrences: issue.resolved_at? ? 1 : issue.occurrences + 1, resolved_at: nil)
        end
      end
    end

    def self.success(statement)
      safely do
        MonitoringIssue.open_issues.where(fingerprint: MonitoringIssue.fingerprint_for(statement)).update_all(resolved_at: Time.current)
      end
    end

    def self.safely
      MonitoringIssue.transaction(requires_new: true) { yield }
    rescue StandardError => error
      # Monitoring must not turn an ordinary refresh into a failed refresh.
      Rails.logger.error("[Monitoring] Recording failed: #{error.class}")
      nil
    end
    private_class_method :safely
  end
end
