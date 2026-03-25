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
      raw_response = nil
      safe_result = invoke_safe_wringer_call do
        raw_response = fetch_wringer_response(url, render_js, scrape_options)
      end

      control = normalize_control_result(safe_result)
      if control.present?
        return {
          status: :abort,
          body: control,
          wringer: build_wringer_status(control, raw_response)
        }
      end

      normalized = normalize_fetch_result(safe_result)

      {
        status: :ok,
        body: normalized[:body],
        wringer: build_wringer_status(safe_result, raw_response) || build_wringer_status(normalized, raw_response) || {}
      }
    end

    private

    def invoke_safe_wringer_call(&blk)
      @safe_wringer_call.call(normalize_response: true, &blk)
    rescue ArgumentError
      @safe_wringer_call.call(&blk)
    end

    def fetch_wringer_response(url, render_js, scrape_options)
      wringer_url = @use_wringer.call(url, render_js, scrape_options)

      if @agent.respond_to?(:get)
        @agent.get(wringer_url)
      else
        @agent.get_file(wringer_url)
      end
    end

    def normalize_fetch_result(result)
      return result if result.is_a?(Hash) && result.key?(:body)

      if result.respond_to?(:code) && result.respond_to?(:body)
        {
          body: result.body,
          http_code: result.code.to_i,
          final_url: result.respond_to?(:uri) ? result.uri.to_s : nil
        }
      else
        {
          body: result,
          http_code: 200,
          final_url: nil
        }
      end
    ensure
      unexpected_type =
        !result.is_a?(Hash) &&
        !(result.respond_to?(:code) && result.respond_to?(:body)) &&
        !result.is_a?(String) &&
        !result.nil?
      if unexpected_type
        @logger.debug { "[WringerClient] Unexpected body type: #{result.class}" }
      end
    end

    def abort_structure?(obj)
      obj.is_a?(Array) &&
        obj.length == 2 &&
        obj.first == "abort_update" &&
        obj.last.is_a?(Hash)
    end

    def control_structure?(obj)
      obj.is_a?(Array) &&
        obj.length == 2 &&
        obj.first.is_a?(String)
    end

    def normalize_control_result(result)
      return nil unless control_structure?(result)

      action = result.first
      payload = result.second
      payload = payload.to_h if payload.respond_to?(:to_h)

      unless payload.is_a?(Hash)
        payload = {
          error: "Malformed Wringer control payload",
          error_type: "WringerMalformedControlPayload",
          source: "wringer"
        }
      end

      normalized = payload.transform_keys { |k| k.respond_to?(:to_sym) ? k.to_sym : k }

      case action
      when "abort_update"
        if %w[wringer_unreachable wringer_error].include?(normalized[:error_type].to_s)
          normalized[:original_error_type] = normalized[:error_type]
          normalized[:error_type] = "WringerFetchError"
          normalized[:source] ||= "wringer"
          normalized[:step] ||= "url"
        end
        ["abort_update", normalized]
      when "skip"
        ["abort_update", {
          error: "Wringer skipped request",
          error_type: "WringerSkip",
          source: "wringer"
        }]
      else
        ["abort_update", {
          error: "Unsupported Wringer action: #{action}",
          error_type: "WringerUnsupportedAction",
          source: "wringer"
        }]
      end
    end

    def build_wringer_status(result, raw_response = nil)
      status = nil

      if abort_structure?(result)
        error_payload = result.last
        return nil unless error_payload.is_a?(Hash)

        policy = error_payload[:policy] || error_payload["policy"] || {}
        policy_action = error_payload[:action] || error_payload["action"] || policy[:action] || policy["action"]

        retry_value = error_payload.key?(:retry) ? error_payload[:retry] : error_payload["retry"]
        cache_value = error_payload.key?(:cache) ? error_payload[:cache] : error_payload["cache"]

        retry_value = policy[:retry] if retry_value.nil? && policy.is_a?(Hash) && policy.key?(:retry)
        retry_value = policy["retry"] if retry_value.nil? && policy.is_a?(Hash) && policy.key?("retry")
        cache_value = policy[:cache] if cache_value.nil? && policy.is_a?(Hash) && policy.key?(:cache)
        cache_value = policy["cache"] if cache_value.nil? && policy.is_a?(Hash) && policy.key?("cache")
        error_type = error_payload[:error_type] || error_payload["error_type"]

        status = {
          error_type: error_type,
          source: error_payload[:source] || error_payload["source"],
          retry: retry_value,
          cache: cache_value,
          signals: normalize_signals(error_payload[:signals] || error_payload["signals"]),
          hints: normalize_hints(error_payload[:hints] || error_payload["hints"])
        }

        if raw_response.respond_to?(:code) && raw_response.respond_to?(:uri)
          status[:http_code] = raw_response.code.to_i
          status[:final_url] = raw_response.uri.to_s
        end

        status[:policy_action] = policy_action if policy_action.present?

        canonical_error_type = error_payload[:original_error_type] || error_payload["original_error_type"] || error_type
        canonical = canonical_wringer_signals(
          error_type: canonical_error_type,
          http_code: status[:http_code],
          policy_action: policy_action
        )
        status.merge!(canonical) if canonical.present?
      elsif result.is_a?(Hash)
        code = result[:http_code].to_i

        if [404, 500, 502, 503, 504].include?(code)
          status = {
            error_type: code == 404 ? "http_404" : "http_server_error",
            http_code: code,
            final_url: result[:final_url]
          }.compact
        end
      end

      status ||= {}

      if raw_response
        status[:signals] ||= extract_signals(raw_response)
        status[:hints] ||= extract_hints(raw_response)
      else
        status[:signals] ||= {}
        status[:hints] ||= []
      end

      status[:signals] = normalize_signals(status[:signals])
      status[:hints] = normalize_hints(status[:hints])

      status
    end

    def normalize_signals(value)
      return value if value.is_a?(Hash)

      {}
    end

    def normalize_hints(value)
      return value if value.is_a?(Array)

      []
    end

    def extract_signals(raw_response)
      return {} unless raw_response

      content_type_header =
        if raw_response.respond_to?(:[])
          raw_response["Content-Type"] || raw_response["content-type"]
        end

      body =
        if raw_response.respond_to?(:body)
          raw_response.body.to_s
        else
          raw_response.to_s
        end

      content_type =
        if content_type_header.to_s.include?("json") || looks_like_json?(body)
          "json"
        elsif content_type_header.to_s.include?("html") || looks_like_html?(body)
          "html"
        else
          "unknown"
        end

      {
        content_type: content_type,
        network_status: "ok"
      }
    rescue StandardError
      {}
    end

    def extract_hints(raw_response)
      return [] unless raw_response

      body =
        if raw_response.respond_to?(:body)
          raw_response.body.to_s
        else
          raw_response.to_s
        end

      hints = []
      hints << "empty_body" if body.strip.empty?
      hints
    rescue StandardError
      []
    end

    def looks_like_json?(body)
      value = body.to_s.lstrip
      value.start_with?("{", "[")
    end

    def looks_like_html?(body)
      value = body.to_s.downcase
      value.include?("<html") || value.include?("<!doctype html")
    end

    def canonical_wringer_signals(error_type:, http_code:, policy_action:)
      normalized_error = error_type.to_s
      code = http_code.to_i

      unreachable = normalized_error == "wringer_unreachable"
      received_404 = normalized_error == "http_404" || code == 404
      system_error = normalized_error == "http_server_error" || normalized_error == "wringer_error" || code >= 500

      has_signal = unreachable || received_404 || system_error
      return nil unless has_signal || policy_action.present?

      {
        unreachable: unreachable,
        received_404: received_404,
        system_error: system_error,
        policy_action: policy_action
      }.compact
    end
  end
end
