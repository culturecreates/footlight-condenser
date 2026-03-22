# app/services/dsl/wringer_client.rb
module Dsl
  class WringerClient
    def initialize(agent:, render_js:, scrape_options:, use_wringer:, safe_wringer_call:, logger:)
      @agent = agent
      @render_js = render_js
      @scrape_options = scrape_options
      @use_wringer = use_wringer
      @safe_wringer_call = safe_wringer_call
      @logger = logger
    end

    def fetch(url:, render_js: @render_js, scrape_options: @scrape_options)
      body = @safe_wringer_call.call do
        @agent.get_file(@use_wringer.call(url, render_js, scrape_options))
      end

      {
        status: abort_structure?(body) ? :abort : :ok,
        body: body,
        wringer: build_wringer_status(body)
      }
    end

    private

    def abort_structure?(obj)
      obj.is_a?(Array) &&
        obj.length == 2 &&
        obj.first == "abort_update" &&
        obj.last.is_a?(Hash)
    end

    def build_wringer_status(result)
      return nil unless abort_structure?(result)

      error_payload = result.last
      return nil unless error_payload.is_a?(Hash)

      policy = error_payload[:policy] || error_payload["policy"] || {}

      retry_value = error_payload.key?(:retry) ? error_payload[:retry] : error_payload["retry"]
      cache_value = error_payload.key?(:cache) ? error_payload[:cache] : error_payload["cache"]

      retry_value = policy[:retry] if retry_value.nil? && policy.is_a?(Hash) && policy.key?(:retry)
      retry_value = policy["retry"] if retry_value.nil? && policy.is_a?(Hash) && policy.key?("retry")
      cache_value = policy[:cache] if cache_value.nil? && policy.is_a?(Hash) && policy.key?(:cache)
      cache_value = policy["cache"] if cache_value.nil? && policy.is_a?(Hash) && policy.key?("cache")

      status = {
        error_type: error_payload[:error_type] || error_payload["error_type"],
        retry: retry_value,
        cache: cache_value
      }.compact

      status.presence
    end
  end
end
