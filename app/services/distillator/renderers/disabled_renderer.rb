module Distillator
  module Renderers
    class DisabledRenderer
      def self.call(url:, uri_key:, iframe:, headers: {}, timeout: nil, agent: nil, logger: nil)
        error = "Rendered fetch is disabled"
        {
          status: :abort,
          body: ["abort_update", {
            error: error,
            error_type: "DistillatorRendererDisabled",
            source: "distillator_renderer",
            retry: false,
            cache: false,
            step: "url",
            signals: {
              network_status: "failed",
              renderer: "disabled"
            },
            hints: ["rendered_fetch_disabled"]
          }],
          headers: {},
          final_url: url,
          redirect_chain: [],
          wringer: {
            error_type: "DistillatorRendererDisabled",
            source: "distillator_renderer",
            retry: false,
            cache: false,
            signals: {
              network_status: "failed",
              renderer: "disabled"
            },
            hints: ["rendered_fetch_disabled"]
          },
          http_code: nil,
          raw_body: nil
        }
      end
    end
  end
end
