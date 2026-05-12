require "uri"

module Distillator
  class FetchEligibility
    Result = Struct.new(:eligible, :reason, :policy, :details, keyword_init: true) do
      def eligible?
        eligible
      end

      def legacy_fallback?
        policy == :explicit_legacy_fallback
      end

      def abort?
        policy == :abort
      end
    end

    def self.call(url:, render_js:, scrape_options:, client: nil, guard: Distillator::FetchGuard)
      new(url: url, render_js: render_js, scrape_options: scrape_options, client: client, guard: guard).call
    end

    def initialize(url:, render_js:, scrape_options:, client: nil, guard: Distillator::FetchGuard)
      @url = url
      @render_js = render_js
      @scrape_options = scrape_options.is_a?(Hash) ? scrape_options : {}
      @client = client
      @guard = guard
    end

    def call
      return ineligible(:forced_legacy, :explicit_legacy_fallback) if forced_legacy?
      return ineligible(:client, :explicit_legacy_fallback) if client
      return ineligible(:unsupported_scheme, :abort) unless supported_scheme?
      return ineligible(:blocked_url, :abort, guard_error: guard_result.error, guard_reason: guard_result.reason) unless guard_result.allowed?

      Result.new(
        eligible: true,
        reason: eligibility_reason,
        policy: :native,
        details: details
      )
    end

    private

    attr_reader :url, :render_js, :scrape_options, :client, :guard

    def json_post?
      Distillator::BooleanParam.parse(scrape_options[:json_post] || scrape_options["json_post"])
    end

    def eligibility_reason
      return :rendered_fetch if Distillator::BooleanParam.parse(render_js)
      return :native_http_post if json_post?

      :native_http_get
    end

    def forced_legacy?
      Distillator::BooleanParam.parse(scrape_options[:force_legacy] || scrape_options["force_legacy"])
    end

    def supported_scheme?
      scheme = parsed_uri&.scheme
      %w[http https].include?(scheme)
    end

    def guard_result
      @guard_result ||= guard.check_url(url)
    end

    def parsed_uri
      @parsed_uri ||= URI.parse(url.to_s)
    rescue URI::InvalidURIError
      nil
    end

    def details
      {
        render_js: Distillator::BooleanParam.parse(render_js) == true,
        json_post: json_post? == true,
        forced_legacy: forced_legacy? == true,
        scheme: parsed_uri&.scheme,
        client: client ? client.class.name : nil,
        guard_error: guard_result.error
      }.compact
    end

    def ineligible(reason, policy, extra_details = {})
      Result.new(eligible: false, reason: reason, policy: policy, details: details.merge(extra_details).compact)
    end
  end
end
