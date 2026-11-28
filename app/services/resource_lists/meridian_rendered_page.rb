# frozen_string_literal: true

require "digest"
require "uri"

module ResourceLists
  # Read-only rendered HTML fetch for the Meridian pairing audit.
  #
  # Uses the guarded native renderer, never FetchCacheStore or Wringer's
  # shared URL cache. Ineligible/disabled renderers fail closed, not to
  # static HTML or the legacy backend.
  class MeridianRenderedPage
    Invalid = Class.new(StandardError)
    MAX_HTML_BYTES = 5 * 1024 * 1024

    def self.call(url:)
      result = Distillator::FetchService.fetch_result(
        url: url, render_js: true, scrape_options: {}, mode: :internal
      )
      signals = result.dig(:wringer, :signals).to_h.stringify_keys
      reason = result.dig(:wringer, :error_type).presence ||
        (signals["renderer_unavailable"] ? "renderer_unavailable" : nil) ||
        "status=#{result[:status]} http=#{result[:http_code]}"
      raise Invalid, "Rendered fetch failed (#{reason})" unless result[:status] == :ok && result[:http_code].to_i == 200
      raise Invalid, "Renderer used a legacy or unverified fetch path" unless result[:fetch_path] == "native"
      raise Invalid, "Renderer did not confirm rendered content" unless signals["use_phantomjs"] == true &&
        signals["fetch_backend"].to_s == "phantomjs"
      raise Invalid, "Renderer returned rejected content" if signals["content_success"] == false ||
        signals["content_success"].to_s == "false" ||
        result.dig(:wringer, :policy_action).to_s == "abort_update"

      html = result[:raw_body].is_a?(String) ? result[:raw_body] : result[:body]
      raise Invalid, "Renderer returned empty or oversized HTML" unless html.is_a?(String) &&
        html.bytesize.between?(1, MAX_HTML_BYTES)

      actual_url = result[:final_url].presence || url
      raise Invalid, "Rendered fetch redirected outside configured calendar page" unless equivalent_url?(url, actual_url)

      { html: html, sha256: Digest::SHA256.hexdigest(html), final_url: actual_url,
        content_type: Distillator::FetchService.normalize_headers(result[:headers] || {})[:content_type],
        bytes: html.bytesize, capture_mode: "rendered_native",
        fetch_path: result[:fetch_path], fetch_backend: signals["fetch_backend"] }
    end

    def self.equivalent_url?(expected, actual)
      a, b = URI.parse(expected), URI.parse(actual)
      a.scheme == "https" && b.scheme == "https" && a.host == b.host &&
        a.port == b.port && a.userinfo.nil? && b.userinfo.nil? &&
        a.path.sub(%r{/+\z}, "") == b.path.sub(%r{/+\z}, "") &&
        URI.decode_www_form(a.query.to_s).sort == URI.decode_www_form(b.query.to_s).sort &&
        b.fragment.nil?
    rescue URI::InvalidURIError, ArgumentError
      false
    end
    private_class_method :equivalent_url?
  end
end
