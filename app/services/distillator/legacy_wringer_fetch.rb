module Distillator
  class LegacyWringerFetch
    def self.fetch(
      url:,
      render_js:,
      scrape_options:,
      client: nil,
      agent: nil,
      use_wringer: nil,
      safe_wringer_call: nil,
      logger: nil
    )
      return fetch_with_client(client, url: url, render_js: render_js, scrape_options: scrape_options) if client

      client = Dsl::Support::WringerClient.new(
        agent: agent || Mechanize.new,
        render_js: render_js,
        scrape_options: scrape_options,
        use_wringer: use_wringer || ApplicationController.helpers.method(:use_wringer),
        safe_wringer_call: safe_wringer_call || ApplicationController.helpers.method(:safe_wringer_call),
        logger: logger || Rails.logger
      )

      client.fetch(url: url)
    end

    def self.fetch_wringer_backed(url:, render_js:, scrape_options:, agent:, use_wringer:, safe_wringer_call:, logger:)
      agent = agent || Mechanize.new
      use_wringer = use_wringer || ApplicationController.helpers.method(:use_wringer)
      safe_wringer_call = safe_wringer_call || ApplicationController.helpers.method(:safe_wringer_call)
      logger = logger || Rails.logger

      raw_response = nil
      safe_result = Distillator::FetchService.invoke_safe_wringer_call(safe_wringer_call) do
        raw_response = fetch_wringer_response(
          agent: agent,
          use_wringer: use_wringer,
          url: url,
          render_js: render_js,
          scrape_options: scrape_options
        )
      end

      control = Distillator::FetchService.normalize_control_result(safe_result)
      if control.present?
        metadata = Distillator::FetchService.fetch_metadata(
          Distillator::FetchService.normalize_fetch_result(raw_response, logger),
          raw_response,
          agent
        )
        return {
          status: :abort,
          body: control,
          headers: metadata[:headers],
          final_url: metadata[:final_url],
          redirect_chain: metadata[:redirect_chain],
          wringer: Distillator::FetchService.build_wringer_status(control, raw_response),
          http_code: raw_response.respond_to?(:code) ? raw_response.code.to_i : nil,
          raw_body: raw_response.respond_to?(:body) ? raw_response.body : nil
        }
      end

      normalized = Distillator::FetchService.normalize_fetch_result(safe_result, logger)
      metadata = Distillator::FetchService.fetch_metadata(normalized, raw_response, agent)

      {
        status: :ok,
        body: normalized[:body],
        headers: metadata[:headers],
        final_url: metadata[:final_url],
        redirect_chain: metadata[:redirect_chain],
        wringer: Distillator::FetchService.build_wringer_status(safe_result, raw_response) ||
                 Distillator::FetchService.build_wringer_status(normalized, raw_response) || {},
        http_code: normalized[:http_code],
        raw_body: raw_response.respond_to?(:body) ? raw_response.body : normalized[:body]
      }
    end

    def self.fetch_with_client(client, url:, render_js:, scrape_options:)
      if client.is_a?(Dsl::Support::WringerClient)
        client.fetch(url: url, render_js: render_js, scrape_options: scrape_options)
      else
        client.fetch(url: url)
      end
    end

    def self.fetch_wringer_response(agent:, use_wringer:, url:, render_js:, scrape_options:)
      wringer_url = use_wringer.call(url, render_js, scrape_options)

      if agent.respond_to?(:get)
        agent.get(wringer_url)
      else
        agent.get_file(wringer_url)
      end
    end

    private_class_method :fetch_with_client, :fetch_wringer_response
  end
end
