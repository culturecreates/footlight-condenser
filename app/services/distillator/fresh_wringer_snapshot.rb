require "json"
require "net/http"
require "time"

module Distillator
  # Wringer may return last-good HTML after a failed scrape. Every attempt must
  # independently confirm a successful scrape before the HTML can be compared.
  class FreshWringerSnapshot
    RETRYABLE_STATUS_CODES = [429, 500, 502, 503, 504].freeze
    TRANSIENT_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Errno::ETIMEDOUT, Errno::ECONNRESET, EOFError].freeze
    RETRY_DELAYS = [0.5, 1.0].freeze
    MAX_RETRY_DELAY = 5
    REQUEST_TIMEOUT = 60

    def self.call(...)
      new(...).call
    end

    def initialize(uri:, render_js: false, include_fragment: false, wringer_endpoint: nil, retry_budget: nil)
      @endpoint = wringer_endpoint || Distillator::WringerEndpoint.current
      @query = { uri: uri, force_scrape: true }
      @query[:use_phantomjs] = true if render_js
      @query[:include_fragment] = true if include_fragment
      @retry_budget = retry_budget
      @metadata = { requested_at: Time.current.iso8601(6), force_scrape: true, render_js: render_js }
    end

    def call
      return failure("missing_config", "Fresh Wringer endpoint is not configured").merge(fetch: @metadata) if @endpoint.legacy_lookup_base_url.blank?

      attempts = []
      result = failure("unreachable", "Transition time budget reached before a fresh Wringer request")
      stop_reason = nil
      loop do
        timeout = [REQUEST_TIMEOUT, @retry_budget&.call].compact.min
        if timeout <= 0
          stop_reason = "transition_budget"
          break
        end

        attempt = { number: attempts.length + 1, requested_at: Time.current.iso8601(6) }
        result = request_snapshot(attempt, timeout: timeout)
        attempt[:status] = result[:status]
        attempts << attempt
        break unless attempt[:retryable]

        backoff = RETRY_DELAYS[attempts.length - 1]
        unless backoff
          stop_reason = "attempt_limit"
          break
        end
        delay = [backoff, attempt[:retry_after_seconds]].compact.max
        if delay > MAX_RETRY_DELAY
          stop_reason = "retry_after_exceeds_limit"
          break
        end
        remaining = @retry_budget&.call
        if remaining && remaining <= delay
          stop_reason = "transition_budget"
          break
        end

        attempt[:backoff_seconds] = delay
        sleep(delay)
      end

      final_http = attempts.last.to_h.slice(:received_at, :response_http_code, :upstream_http_code)
      result.merge(fetch: @metadata.merge(final_http).merge(attempts: attempts, recovered: result[:status] == "ok" && attempts.length > 1,
        retry_stopped: stop_reason).compact)
    end

    private

    def request_snapshot(attempt, timeout:)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = HTTParty.get("#{@endpoint.legacy_lookup_base_url}/websites/wring.json", query: @query, timeout: timeout, max_retries: 0)
      attempt[:received_at] = Time.current.iso8601(6)
      attempt[:response_http_code] = response.code.to_i
      unless response.code.to_i.in?(200..299)
        record_http_retry(attempt, response.code.to_i, response.headers)
        return failure("unreachable", "Fresh Wringer request returned HTTP #{response.code}")
      end

      payload = JSON.parse(response.body)
      return failure("unreachable", "Fresh Wringer response is not an object") unless payload.is_a?(Hash)

      code = payload["http_code"] || payload["http_response_code"]
      attempt[:upstream_http_code] = code
      signals = payload["signals"].to_h.stringify_keys
      unless code.to_i.in?(200..299)
        issues = [signals["blocking_issue_key"], signals["primary_issue_key"], *Array(payload["hints"])]
        unless signals["cf_mitigated"].to_s.casecmp?("challenge") || issues.any? { |issue| issue.to_s.match?(/captcha|cloudflare|queue_it/i) }
          record_http_retry(attempt, code.to_i, payload["headers"].to_h)
        end
        return failure("unreachable", "Fresh Wringer scrape did not confirm HTTP 2xx (#{code || 'unknown'}); cached HTML rejected")
      end

      failed = signals["network_status"] == "failed" ||
        %w[transport_success content_success].any? { |key| signals.key?(key) && !Distillator::BooleanParam.parse(signals[key]) } ||
        signals["blocking_issue_key"].present? || signals["primary_issue_key"].present? ||
        (payload["cache"] || signals["cache"]) == "abort_update"
      return failure("unreachable", "Fresh Wringer scrape failed; cached HTML rejected") if failed
      return failure("body_omitted", "Fresh Wringer scrape returned no HTML") unless payload["html"].is_a?(String) && payload["html"].present?

      challenge = Distillator::WringerSystemErrorMatcher.all_matches(
        body: payload["html"], http_code: code,
        final_url: payload["final_url"].presence || @query[:uri],
        hints: Array(payload["hints"]), signals: signals
      ).find { |issue| issue[:key] == "browser_challenge_interstitial" }

      if challenge
        return failure("unreachable", "Fresh Wringer returned browser verification challenge; cached HTML rejected")
      end

      { payload: payload, source: "remote_wringer_fresh", status: "ok", error: nil }
    rescue StandardError => error
      attempt[:error_class] = error.class.name
      attempt[:retryable] = TRANSIENT_ERRORS.any? { |type| error.is_a?(type) }
      failure("unreachable", "Fresh Wringer fetch failed: #{error.message}")
    ensure
      attempt[:duration_ms] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(2)
    end

    def record_http_retry(attempt, code, headers)
      headers = Distillator::FetchService.normalize_headers(headers.to_h)
      return unless RETRYABLE_STATUS_CODES.include?(code) && !Array(headers[:cf_mitigated]).first.to_s.strip.casecmp?("challenge")

      attempt[:retryable] = true
      hint = Array(headers[:retry_after]).first.to_s.strip
      return if hint.blank?

      attempt[:retry_after_seconds] = if hint.match?(/\A[0-9]+\z/)
        hint.to_i
      else
        [(Time.httpdate(hint) - Time.current).ceil, 0].max
      end
    rescue ArgumentError
      # An unusable Retry-After header still allows the bounded default backoff.
      nil
    end

    def failure(status, error)
      { payload: nil, source: "remote_wringer_fresh", status: status, error: error }
    end
  end
end
