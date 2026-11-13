require "json"

module Distillator
  class PhantomjsFetcher
    PHANTOMJS_BASE_URL = "https://phantomjscloud.com/api/browser/v2".freeze

    def self.call(url:, uri_key:, iframe:, headers: {}, timeout: nil, agent: nil, logger: nil)
      logger = logger || Rails.logger

      if ENV["PHANTOMJS_API_KEY"].blank?
        logger.error("PHANTOMJS_API_KEY is not set for rendered fetch")
        return direct_fallback_with_unavailable_renderer(url: url, iframe: iframe, agent: agent, logger: logger) if allow_direct_fallback?

        return renderer_unavailable_result(url: url, iframe: iframe)
      end

      result = Distillator::NativeFetch.call(
        url: request_url(url: url, iframe: iframe),
        render_js: false,
        scrape_options: {},
        agent: agent,
        logger: logger
      )
      result = extract_iframe_content(result) if iframe
      result[:final_url] = url if result[:final_url].blank? || result[:final_url].to_s.include?(PHANTOMJS_BASE_URL)
      annotate(result, iframe: iframe)
    end

    def self.request_url(url:, iframe:)
      api_key = ENV.fetch("PHANTOMJS_API_KEY")
      output_as_json = iframe ? "true" : "false"
      request = "{url:%22#{url}%22,renderType:%22html%22,outputAsJson:#{output_as_json},requestSettings:{ignoreImages:true, waitInterval:2500 }}"

      "#{PHANTOMJS_BASE_URL}/#{api_key}/?request=#{request}"
    end

    def self.extract_iframe_content(result)
      return iframe_extraction_failure(result, "phantomjs_iframe_missing_response_body") unless result[:status] == :ok && result[:body].is_a?(String)

      parsed = JSON.parse(result[:body])
      iframe_html = parsed.dig("pageResponses", 0, "frameData", "childFrames", 0, "content")
      return iframe_extraction_failure(result, "phantomjs_iframe_missing_child_content") if iframe_html.blank?

      result.merge(
        body: iframe_html,
        raw_body: iframe_html,
        wringer: merge_wringer_metadata(result[:wringer], signals: { phantomjs_iframe_extraction: true })
      )
    rescue JSON::ParserError, TypeError
      iframe_extraction_failure(result, "phantomjs_iframe_malformed_json")
    end

    def self.annotate(result, fallback: nil, iframe: false)
      payload = result.deep_dup
      payload[:wringer] = merge_wringer_metadata(
        payload[:wringer],
        signals: {
          renderer: "legacy_phantomjs",
          renderer_unavailable: fallback.present?,
          fetch_backend: fallback.present? ? "native" : "phantomjs",
          request_method: "GET",
          use_phantomjs: true,
          phantomjs_iframe_extraction: iframe && payload.dig(:wringer, :signals, :phantomjs_iframe_extraction) != true ? false : payload.dig(:wringer, :signals, :phantomjs_iframe_extraction) == true
        },
        hints: ["legacy_phantomjs", ("phantomjs_unavailable" if fallback.present?)].compact
      )
      payload[:wringer][:signals][:renderer_fallback] = fallback if fallback.present?
      payload
    end

    def self.renderer_unavailable_result(url:, iframe:)
      {
        status: :abort,
        body: [
          "abort_update",
          {
            error: "Legacy PhantomJS renderer is unavailable",
            error_type: "DistillatorRendererUnavailable",
            source: "phantomjs_fetcher",
            retry: true,
            cache: false,
            step: "url",
            signals: {
              network_status: "failed",
              renderer: "legacy_phantomjs",
              renderer_unavailable: true,
              renderer_fallback: "none",
              use_phantomjs: true,
              phantomjs_iframe_extraction: iframe
            },
            hints: ["legacy_phantomjs", "phantomjs_unavailable"]
          }
        ],
        headers: {},
        final_url: url,
        redirect_chain: [],
        wringer: {
          error_type: "DistillatorRendererUnavailable",
          source: "phantomjs_fetcher",
          retry: true,
          cache: false,
          signals: {
            network_status: "failed",
            renderer: "legacy_phantomjs",
            renderer_unavailable: true,
            renderer_fallback: "none",
            use_phantomjs: true,
            phantomjs_iframe_extraction: iframe
          },
          hints: ["legacy_phantomjs", "phantomjs_unavailable"]
        },
        http_code: nil,
        raw_body: nil
      }
    end

    def self.direct_fallback_with_unavailable_renderer(url:, iframe:, agent:, logger:)
      annotate(
        Distillator::NativeFetch.call(
          url: url,
          render_js: false,
          scrape_options: {},
          agent: agent,
          logger: logger
        ),
        fallback: "direct_url",
        iframe: iframe
      )
    end

    def self.allow_direct_fallback?
      Distillator::BooleanParam.parse(ENV["DISTILLATOR_ALLOW_RENDERED_DIRECT_FALLBACK"])
    end

    def self.iframe_extraction_failure(result, hint)
      {
        status: :abort,
        body: [
          "abort_update",
          {
            error: hint.humanize,
            error_type: "PhantomjsIframeExtractionError",
            source: "phantomjs_fetcher",
            retry: true,
            cache: false,
            step: "iframe",
            signals: { phantomjs_iframe_extraction: false },
            hints: [hint]
          }
        ],
        headers: result[:headers] || {},
        final_url: result[:final_url],
        redirect_chain: result[:redirect_chain] || [],
        wringer: merge_wringer_metadata(
          result[:wringer],
          signals: { phantomjs_iframe_extraction: false },
          hints: [hint]
        ),
        http_code: nil,
        raw_body: nil
      }
    end

    def self.merge_wringer_metadata(wringer, signals: {}, hints: [])
      payload = (wringer || {}).deep_dup
      payload[:signals] = Distillator::FetchService.normalize_signals(payload[:signals]).merge(signals)
      payload[:hints] = (Distillator::FetchService.normalize_hints(payload[:hints]) + hints).uniq
      payload
    end

    private_class_method :annotate
  end
end
