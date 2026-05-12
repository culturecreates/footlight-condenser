module Distillator
  class NativeFetch
    BROWSER_USER_AGENT_ALIAS = "Mac Safari".freeze
    HTTP_SERVER_ERROR_CODES = [500, 502, 503, 504].freeze
    NETWORK_ERRORS = [
      OpenSSL::SSL::SSLError,
      Mechanize::Error,
      SocketError,
      Net::OpenTimeout,
      Net::ReadTimeout,
      Timeout::Error
    ].freeze

    def self.call(url:, render_js:, scrape_options:, agent: nil, logger: nil)
      logger = logger || Rails.logger
      if render_js
        return Distillator::RenderedFetch.call(
          url: url,
          uri_key: scrape_options[:uri_key] || scrape_options["uri_key"] || Distillator::WringerUrlKey.call(url).uri_key,
          iframe: iframe_request?(url: url, scrape_options: scrape_options),
          agent: agent,
          logger: logger
        )
      end

      agent = configure_agent(agent || Mechanize.new)
      log_request(logger, url: url, render_js: render_js, scrape_options: scrape_options)

      raw_response = fetch_response(agent, url, scrape_options)
      finalize_result(
        url: url,
        result: build_success_or_http_failure(raw_response, agent, logger),
        scrape_options: scrape_options,
        logger: logger
      )
    rescue Mechanize::ResponseCodeError => error
      raw_response = response_from_error(error)
      raise error unless raw_response

      finalize_result(
        url: url,
        result: build_success_or_http_failure(raw_response, agent, logger),
        scrape_options: scrape_options,
        logger: logger
      )
    rescue OpenSSL::SSL::SSLError => error
      retry_result = retry_with_ssl_verify_none(agent, url, scrape_options, logger)
      return finalize_result(url: url, result: retry_result, scrape_options: scrape_options, logger: logger) if retry_result

      finalize_result(
        url: url,
        result: failed_network_result(error),
        scrape_options: scrape_options,
        logger: logger
      )
    rescue *NETWORK_ERRORS => error
      finalize_result(
        url: url,
        result: failed_network_result(error),
        scrape_options: scrape_options,
        logger: logger
      )
    end

    def self.fetch(url:, render_js:, scrape_options:, agent: nil, logger: nil)
      call(
        url: url,
        render_js: render_js,
        scrape_options: scrape_options,
        agent: agent,
        logger: logger
      )
    end

    def self.fetch_response(agent, url, scrape_options)
      return fetch_post_response(agent, url, scrape_options) if Distillator::FetchService.json_post?(scrape_options) == true

      if agent.respond_to?(:get)
        agent.get(url)
      else
        agent.get_file(url)
      end
    end

    def self.build_success_or_http_failure(raw_response, agent, logger)
      normalized = Distillator::FetchService.normalize_fetch_result(raw_response, logger)
      metadata = Distillator::FetchService.fetch_metadata(normalized, raw_response, agent)
      control = Distillator::FetchService.normalize_control_result(normalized[:body])
      http_code = normalized[:http_code].to_i

      if control.present?
        return control_result(control: control, metadata: metadata, raw_response: raw_response)
      end

      if http_code == 404 || HTTP_SERVER_ERROR_CODES.include?(http_code)
        return http_failure_result(http_code: http_code, metadata: metadata, raw_response: raw_response)
      end

      {
        status: :ok,
        body: normalized[:body],
        headers: metadata[:headers],
        final_url: metadata[:final_url],
        redirect_chain: metadata[:redirect_chain],
        wringer: Distillator::FetchService.build_wringer_status(normalized, raw_response) || {},
        http_code: http_code,
        raw_body: normalized[:body]
      }
    end

    def self.control_result(control:, metadata:, raw_response:)
      {
        status: :abort,
        body: control,
        headers: metadata[:headers],
        final_url: metadata[:final_url],
        redirect_chain: metadata[:redirect_chain],
        wringer: Distillator::FetchService.build_wringer_status(control, raw_response),
        http_code: nil,
        raw_body: nil
      }
    end

    def self.http_failure_result(http_code:, metadata:, raw_response:)
      error_type = http_code == 404 ? "http_404" : "http_server_error"
      retry_value = http_code == 404 ? false : true
      control = [
        "abort_update",
        {
          error: "HTTP #{http_code}",
          error_type: error_type,
          source: "native_fetch",
          step: "url",
          policy: {
            action: "abort_update",
            retry: retry_value,
            cache: false
          }
        }
      ]

      {
        status: :abort,
        body: control,
        headers: metadata[:headers],
        final_url: metadata[:final_url],
        redirect_chain: metadata[:redirect_chain],
        wringer: Distillator::FetchService.build_wringer_status(control, raw_response),
        http_code: http_code,
        raw_body: raw_response.respond_to?(:body) ? raw_response.body : nil
      }
    end

    def self.failed_network_result(error)
      timeout = timeout_error?(error)
      hints = timeout ? ["timeout"] : []
      control = [
        "abort_update",
        {
          error: error.message,
          error_type: "NativeFetchError",
          source: "native_fetch",
          retry: true,
          cache: false,
          step: "url",
          signals: { network_status: "failed", timeout: timeout },
          hints: hints
        }
      ]

      {
        status: :abort,
        body: control,
        headers: {},
        final_url: nil,
        redirect_chain: [],
        wringer: Distillator::FetchService.build_wringer_status(control),
        http_code: nil,
        raw_body: nil
      }
    end

    def self.finalize_result(url:, result:, scrape_options:, logger:)
      payload = Distillator::FetchService.enrich_wringer_metadata(url: url, result: result)
      payload = annotate_request_metadata(payload, scrape_options: scrape_options)
      log_response(logger, payload)
      payload
    end

    def self.timeout_error?(error)
      error.is_a?(Net::OpenTimeout) ||
        error.is_a?(Net::ReadTimeout) ||
        error.message.to_s.downcase.include?("timeout")
    end

    def self.response_from_error(error)
      return error.page if error.respond_to?(:page) && error.page
      return error.response if error.respond_to?(:response) && error.response

      nil
    end

    def self.log_request(logger, url:, render_js:, scrape_options:)
      logger.info(
        event: "distillator.native_fetch.request",
        url: url,
        render_js: Distillator::BooleanParam.parse(render_js),
        json_post: Distillator::FetchService.json_post?(scrape_options) == true
      )
    end

    def self.fetch_post_response(agent, url, scrape_options)
      Distillator::JsonPostFetcher.call(agent: agent, url: url, scrape_options: scrape_options)
    end

    def self.configure_agent(agent)
      if agent.public_methods.include?(:user_agent_alias=)
        agent.user_agent_alias = BROWSER_USER_AGENT_ALIAS
      end
      agent
    end

    def self.retry_with_ssl_verify_none(agent, url, scrape_options, logger)
      return nil unless ssl_retry_supported?(agent)

      set_ssl_verify_none(agent)
      logger.warn(event: "distillator.native_fetch.ssl_retry", url: url, verify_mode: "VERIFY_NONE") if logger.respond_to?(:warn)

      raw_response = fetch_response(agent, url, scrape_options)
      result = build_success_or_http_failure(raw_response, agent, logger)
      result[:wringer] = (result[:wringer] || {}).deep_dup
      result[:wringer][:signals] = Distillator::FetchService.normalize_signals(result.dig(:wringer, :signals)).merge(ssl_verify_none_fallback: true)
      result[:wringer][:hints] = (Distillator::FetchService.normalize_hints(result.dig(:wringer, :hints)) + ["ssl_verify_none_fallback"]).uniq
      result
    rescue *NETWORK_ERRORS
      nil
    end

    def self.ssl_retry_supported?(agent)
      ssl_http(agent).present?
    end

    def self.set_ssl_verify_none(agent)
      ssl_http(agent).verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    def self.ssl_http(agent)
      wrapped_agent = agent.agent
      return unless wrapped_agent.respond_to?(:http)

      wrapped_agent.http
    rescue StandardError
      nil
    end

    def self.annotate_request_metadata(result, scrape_options:)
      payload = result.deep_dup
      payload[:wringer] ||= {}
      payload[:wringer][:signals] = Distillator::FetchService.normalize_signals(payload.dig(:wringer, :signals)).merge(
        fetch_backend: "native",
        request_method: Distillator::FetchService.json_post?(scrape_options) ? "POST" : "GET",
        use_phantomjs: false,
        phantomjs_iframe_extraction: false
      )
      payload
    end

    def self.log_response(logger, result)
      logger.info(
        event: "distillator.native_fetch.response",
        status: result[:status],
        http_code: result[:http_code],
        final_url: result[:final_url],
        redirect_chain: result[:redirect_chain] || [],
        headers: result[:headers] || {},
        signals: result.dig(:wringer, :signals) || {},
        hints: result.dig(:wringer, :hints) || []
      )
    end

    def self.iframe_request?(url:, scrape_options:)
      return true if Distillator::BooleanParam.parse(scrape_options[:iframe] || scrape_options["iframe"])

      Distillator::WringerUrlKey.call(url).uri_key.end_with?("iframe")
    end

    private_class_method(
      :fetch_response,
      :fetch_post_response,
      :build_success_or_http_failure,
      :control_result,
      :http_failure_result,
      :failed_network_result,
      :finalize_result,
      :timeout_error?,
      :response_from_error,
      :log_request,
      :log_response,
      :iframe_request?,
      :configure_agent,
      :retry_with_ssl_verify_none,
      :ssl_retry_supported?,
      :set_ssl_verify_none,
      :ssl_http,
      :annotate_request_metadata
    )
  end
end
