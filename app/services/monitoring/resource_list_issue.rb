module Monitoring
  class ResourceListIssue
    def self.observe(kind, website:, page:, at:, message:, evidence: {}, source_id: nil)
      key = fingerprint(kind, website, page)
      issue = MonitoringIssue.create_or_find_by!(fingerprint: key) do |record|
        record.assign_attributes(kind: kind, seedurl: website.seedurl, website_name: website.name, url: page.url,
          webpage_id: page.id, source_id: source_id, message: message, evidence: evidence,
          first_seen_at: at, last_seen_at: at, occurrences: 0)
      end
      issue.with_lock do
        next if issue.occurrences.positive? && at <= (issue.resolved_at || issue.last_seen_at)

        issue.update!(seedurl: website.seedurl, website_name: website.name, url: page.url, webpage_id: page.id,
          source_id: source_id, message: message, evidence: evidence, last_seen_at: at,
          first_seen_at: issue.resolved_at? ? at : issue.first_seen_at,
          occurrences: issue.resolved_at? ? 1 : issue.occurrences + 1, resolved_at: nil)
      end
    end

    def self.resolve(kind, website:, page:, at:)
      MonitoringIssue.open_issues.where(fingerprint: fingerprint(kind, website, page))
        .where("last_seen_at <= ?", at).update_all(resolved_at: at)
    end

    def self.fingerprint(kind, website, page)
      identity = kind == "possible_missed_event" ? page.url : page.id
      Digest::SHA256.hexdigest("#{kind}:#{website.id}:#{identity}")
    end
    private_class_method :fingerprint
  end
end
