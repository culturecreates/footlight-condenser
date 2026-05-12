require "uri"

module Distillator
  class CacheHealth
    STALE_AFTER = 7.days

    STATUS_META = {
      blocked: { label: "Blocked", severity: "high" },
      network_failed: { label: "Network failed", severity: "high" },
      never_fetched: { label: "Never fetched", severity: "medium" },
      attempt_failed: { label: "Attempt failed", severity: "high" },
      empty_body: { label: "Empty body", severity: "medium" },
      preserved_after_failure: { label: "Preserved after failure", severity: "medium" },
      redirect_changed: { label: "Redirect changed", severity: "low" },
      stale: { label: "Stale", severity: "low" },
      healthy: { label: "Healthy", severity: "ok" },
      unknown: { label: "Unknown", severity: "unknown" }
    }.freeze

    Result = Struct.new(:status, :label, :severity, :reasons, keyword_init: true) do
      def as_json(*)
        {
          health_status: status.to_s,
          health_label: label,
          health_severity: severity,
          health_reasons: reasons
        }
      end
    end

    def self.call(cache, stale_after: STALE_AFTER)
      new(cache, stale_after: stale_after).call
    end

    def initialize(cache, stale_after: STALE_AFTER)
      @cache = cache
      @stale_after = stale_after
    end

    def call
      return build(:blocked, ["blocked"]) if blocked?
      return build(:network_failed, ["network_failed"]) if network_failed?
      return build(:never_fetched, ["never_fetched"]) if never_fetched?
      return build(:attempt_failed, [failure_reason]) if attempt_failed?
      return build(:empty_body, ["empty_body"]) if empty_body?
      return build(:preserved_after_failure, ["non_2xx_preserved_html"]) if preserved_after_failure?
      return build(:redirect_changed, ["redirect_changed"]) if redirect_changed?
      return build(:stale, ["stale"]) if stale?
      return build(:healthy, ["successful_2xx_refresh"]) if healthy?

      build(:unknown, ["unknown"])
    end

    private

    attr_reader :cache, :stale_after

    def build(status, reasons)
      meta = STATUS_META.fetch(status)
      Result.new(
        status: status,
        label: meta.fetch(:label),
        severity: meta.fetch(:severity),
        reasons: reasons
      )
    end

    def blocked?
      hints.include?("blocked") ||
        signal("error_type") == "DistillatorFetchBlocked" ||
        signal("network_status") == "blocked"
    end

    def network_failed?
      signal("network_status") == "failed"
    end

    def never_fetched?
      cache.scrape_date.blank? && cache.http_response_code.blank? && cache.successful_refresh.blank?
    end

    def empty_body?
      hints.include?("empty_body") || signal("empty_body") == true
    end

    def attempt_failed?
      return false unless scrape_attempted?
      return false if preserved_after_failure?
      return false if healthy?

      blocking_content_failure?
    end

    def preserved_after_failure?
      scrape_attempted? &&
        has_html? &&
        cache.successful_refresh.present? &&
        cache.scrape_date.present? &&
        cache.successful_refresh < cache.scrape_date &&
        blocking_content_failure?
    end

    def redirect_changed?
      normalized_host = host_for(cache.normalized_url)
      final_host = host_for(cache.final_url)
      normalized_host.present? && final_host.present? && normalized_host != final_host
    end

    def stale?
      return false if stale_after.blank?
      return false if cache.scrape_date.blank?

      cache.scrape_date < Time.current - stale_after
    end

    def healthy?
      truthy_signal?("content_success") ||
        (success_2xx?(cache.http_response_code) && has_html? && cache.successful_refresh.present?)
    end

    def scrape_attempted?
      cache.scrape_date.present? || cache.http_response_code.present?
    end

    def blocking_content_failure?
      return true if %w[blocked failed].include?(signal("primary_issue_severity").to_s)
      return true if signal("content_success") == false || signal("content_success").to_s == "false"
      return true if non_2xx?(cache.http_response_code)

      false
    end

    def failure_reason
      signal("primary_issue_key").presence || "attempt_failed"
    end

    def has_html?
      cache.html.present?
    end

    def success_2xx?(code)
      code.to_i.between?(200, 299)
    end

    def non_2xx?(code)
      code.present? && !success_2xx?(code)
    end

    def hints
      @hints ||= Array(cache.hints).map(&:to_s)
    end

    def signal(key)
      signals[key.to_s] || signals[key.to_sym]
    end

    def signals
      @signals ||= (cache.signals || {}).to_h
    end

    def truthy_signal?(key)
      value = signal(key)
      value == true || value.to_s == "true" || value.to_s == "1"
    end

    def host_for(url)
      URI.parse(url.to_s).host
    rescue URI::InvalidURIError
      nil
    end
  end
end
