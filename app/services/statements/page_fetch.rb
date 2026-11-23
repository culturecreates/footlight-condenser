module Statements
  class PageFetch
    attr_reader :render_js, :json_post

    def initialize(render_js:, scrape_options:)
      @render_js = render_js || Distillator::BooleanParam.parse(scrape_options[:use_phantomjs])
      @json_post = Distillator::BooleanParam.parse(scrape_options[:json_post])
    end

    def call
      # Reuse the first result, including failures. Each DSL runner can mutate its copy.
      @result ||= yield
      @result.deep_dup
    end
  end
end
