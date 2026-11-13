# app/services/dsl/support/wringer_client.rb
module Dsl
  module Support
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
        Distillator::FetchService.fetch_wringer_backed(
          url: url,
          render_js: render_js,
          scrape_options: scrape_options,
          agent: @agent,
          use_wringer: @use_wringer,
          safe_wringer_call: @safe_wringer_call,
          logger: @logger
        )
      end
    end
  end
end
