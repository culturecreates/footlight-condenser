module Distillator
  class RefreshRunner
    DEFAULT_SCRAPE_OPTIONS = { force_scrape_every_hrs: 1 }.freeze

    def self.call(webpage:, refresh_helper:, scrape_options: {})
      Statements::RefreshWebpageStatementsService.new(refresh_helper: refresh_helper).call(
        webpage: webpage,
        default_language: webpage.website.default_language,
        scrape_options: normalized_scrape_options(scrape_options)
      )
    end

    def self.normalized_scrape_options(scrape_options)
      options = scrape_options.respond_to?(:to_h) ? scrape_options.to_h.symbolize_keys : {}
      DEFAULT_SCRAPE_OPTIONS.merge(options.compact)
    end
  end
end
