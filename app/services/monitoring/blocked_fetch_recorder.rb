module Monitoring
  class BlockedFetchRecorder
    def self.call(result, website:, context:)
      backend = result.signals.to_h["fetch_backend"]
      return unless %w[native legacy].include?(backend) && context[:website_id] && context[:source_id]

      website = Website.find_by(id: context[:website_id]) if website&.id != context[:website_id]
      return unless website&.monitorable?

      headers = Distillator::FetchService.normalize_headers(result.headers)
      if backend == "legacy"
        # The raw Wringer endpoint serves last-good HTML with its own HTTP 200.
        # Only upstream metadata can establish failure or recovery here.
        code = Array(headers[:x_wringer_upstream_status]).first.to_i
        attempt = Array(headers[:x_wringer_last_attempt_at]).first&.to_time
        success = Array(headers[:x_wringer_last_success_at]).first&.to_time
        cloudflare = {}
      else
        code = result.http_response_code.to_i
        attempt = result.scrape_date
        success = result.successful_refresh
        cloudflare = Distillator::FetchService.cloudflare_response_headers(headers, signals: result.signals)
      end
      return unless attempt

      fingerprint = Digest::SHA256.hexdigest("blocked_fetch:#{website.id}:#{backend}:#{result.uri_key}")
      if code == 403 || cloudflare[:cf_mitigated] == "challenge"
        label = backend == "legacy" ? "Wringer" : "Condenser"
        detail = cloudflare[:cf_mitigated] == "challenge" ? "Cloudflare challenge (HTTP #{code})" : "HTTP 403"
        message = ["#{label} reported #{detail}.", "Last successful source refresh #{success&.getutc&.iso8601 || 'not recorded'}.",
          ("Cached HTML remains available." if result.html.present?), ("CF-Ray #{cloudflare[:cf_ray]}." if cloudflare[:cf_ray])].compact.join(" ")
        record_failure(fingerprint, website, result, context, attempt, message)
      elsif code.between?(200, 299) && result.content_success? && success && success >= attempt
        MonitoringIssue.transaction(requires_new: true) do
          MonitoringIssue.open_issues.where(fingerprint: fingerprint).where("last_seen_at < ?", success).update_all(resolved_at: success)
        end
      end
    rescue StandardError => error
      Rails.logger.error("[Monitoring] Blocked fetch recording failed: #{error.class}")
    end

    def self.record_failure(fingerprint, website, result, context, attempt, message)
      MonitoringIssue.transaction(requires_new: true) do
        issue = MonitoringIssue.create_or_find_by!(fingerprint: fingerprint) do |record|
          record.assign_attributes(kind: "blocked_fetch", seedurl: website.seedurl, website_name: website.name,
            url: result.normalized_url, source_id: context[:source_id], statement_id: context[:statement_id],
            property_name: "Source fetch", message: message, first_seen_at: attempt, last_seen_at: attempt, occurrences: 0)
        end
        issue.with_lock do
          next if issue.occurrences.positive? && attempt <= (issue.resolved_at || issue.last_seen_at)

          issue.update!(message: message, first_seen_at: issue.resolved_at? ? attempt : issue.first_seen_at,
            last_seen_at: attempt, occurrences: issue.resolved_at? ? 1 : issue.occurrences + 1, resolved_at: nil)
        end
      end
    end
    private_class_method :record_failure
  end
end
