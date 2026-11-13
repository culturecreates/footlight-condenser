require "json"

module Distillator
  # Request a new legacy fetch, never a cache lookup. Wringer can return its
  # last-good HTML after a failed scrape, so HTML alone is not success evidence.
  class FreshWringerSnapshot
    def self.call(uri:, render_js: false, include_fragment: false, wringer_endpoint: nil)
      metadata = { requested_at: Time.current.iso8601(6), force_scrape: true, render_js: render_js }
      failure = ->(status, error) {
        { payload: nil, source: "remote_wringer_fresh", status: status, error: error, fetch: metadata }
      }
      endpoint = wringer_endpoint || Distillator::WringerEndpoint.current
      return failure.call("missing_config", "Fresh Wringer endpoint is not configured") if endpoint.legacy_lookup_base_url.blank?

      query = { uri: uri, force_scrape: true }
      query[:use_phantomjs] = true if render_js
      query[:include_fragment] = true if include_fragment
      response = HTTParty.get("#{endpoint.legacy_lookup_base_url}/websites/wring.json", query: query, timeout: 60)
      metadata[:received_at] = Time.current.iso8601(6)
      metadata[:response_http_code] = response.code.to_i
      return failure.call("unreachable", "Fresh Wringer request returned HTTP #{response.code}") unless response.code.to_i.in?(200..299)

      payload = JSON.parse(response.body)
      return failure.call("unreachable", "Fresh Wringer response is not an object") unless payload.is_a?(Hash)

      code = payload["http_code"] || payload["http_response_code"]
      metadata[:upstream_http_code] = code
      return failure.call("unreachable", "Fresh Wringer scrape did not confirm HTTP 2xx (#{code || 'unknown'}); cached HTML rejected") unless code.to_i.in?(200..299)

      signals = payload["signals"].to_h.stringify_keys
      failed = signals["network_status"] == "failed" ||
        %w[transport_success content_success].any? { |key| signals.key?(key) && !Distillator::BooleanParam.parse(signals[key]) } ||
        signals["blocking_issue_key"].present? || signals["primary_issue_key"].present? ||
        (payload["cache"] || signals["cache"]) == "abort_update"
      return failure.call("unreachable", "Fresh Wringer scrape failed; cached HTML rejected") if failed
      return failure.call("body_omitted", "Fresh Wringer scrape returned no HTML") unless payload["html"].is_a?(String) && payload["html"].present?

      { payload: payload, source: "remote_wringer_fresh", status: "ok", error: nil, fetch: metadata }
    rescue StandardError => error
      failure.call("unreachable", "Fresh Wringer fetch failed: #{error.message}")
    end
  end
end
