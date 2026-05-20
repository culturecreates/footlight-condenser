module Distillator
  class TransitionCheckRunner
    Result = Struct.new(:website, :records, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(website:)
      @website = website.is_a?(Website) ? website : Website.find(website)
    end

    def call
      transition_check = Distillator::TransitionCheck.call(website: website)

      Result.new(
        website: website,
        records: {
          fetch_parity: record_fetch_check(transition_check),
          statement_delta: record_statement_check(transition_check),
          export_diff: record_export_check(transition_check)
        }
      )
    end

    private

    attr_reader :website

    def record_fetch_check(transition_check)
      latest_cache = transition_check.cache
      status, details = fetch_check_payload(transition_check)

      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        url: cache_or_seed_url(latest_cache),
        check_kind: :fetch_parity,
        status: status,
        primary_issue_key: latest_cache&.primary_issue_key,
        wringer_http_code: latest_cache&.http_response_code,
        distillator_http_code: latest_cache&.http_response_code,
        details: details
      )
    end

    def record_statement_check(transition_check)
      latest_cache = transition_check.cache
      signal = cache_signal(latest_cache, "statement_count_delta_acceptable")
      status =
        if signal == true || signal.to_s == "true" || signal.to_s == "1"
          :checked
        elsif signal == false || signal.to_s == "false" || signal.to_s == "0"
          :failed
        else
          :pending
        end

      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        url: cache_or_seed_url(latest_cache),
        check_kind: :statement_delta,
        status: status,
        statement_count_delta_acceptable: status == :checked ? true : (status == :failed ? false : nil),
        details: { source: "cache_signals" }
      )
    end

    def record_export_check(transition_check)
      latest_cache = transition_check.cache
      status_value = cache_signal(latest_cache, "export_diff_status").to_s
      checked_value = cache_signal(latest_cache, "export_diff_checked")
      accepted_value = cache_signal(latest_cache, "export_diff_accepted")
      status =
        if %w[checked accepted].include?(status_value) || truthy?(checked_value) || truthy?(accepted_value)
          :checked
        elsif %w[failed blocked rejected].include?(status_value)
          :failed
        else
          :pending
        end

      Distillator::TransitionEvidenceRecorder.call(
        website: website,
        url: cache_or_seed_url(latest_cache),
        check_kind: :export_diff,
        status: status,
        export_diff_checked: status == :checked ? true : nil,
        export_diff_status: status == :pending ? "pending" : status.to_s,
        export_diff_accepted: truthy?(accepted_value),
        details: { source: "cache_signals" }
      )
    end

    def fetch_check_payload(transition_check)
      cache = transition_check.cache
      return [:failed, { reason: "missing_cache" }] unless cache.present?
      return [:failed, { reason: "cache_health_failed" }] if transition_check.fetch == :failed

      [:checked, { representative_urls_checked: true, source: "cache_health" }]
    end

    def cache_or_seed_url(cache)
      cache&.normalized_url.presence || website.webpages.first&.url.presence || website.seedurl
    end

    def cache_signal(cache, key)
      return nil unless cache.present?

      signals = (cache.signals || {}).to_h
      return signals[key.to_s] if signals.key?(key.to_s)
      return signals[key.to_sym] if signals.key?(key.to_sym)

      nil
    end

    def truthy?(value)
      value == true || value.to_s == "true" || value.to_s == "1"
    end
  end
end
