module Distillator
  class CacheFetchCommand
    VALID_KINDS = %w[normal rendered post].freeze

    Result = Struct.new(:ok?, :cache, :message, :errors, :fetch_result, keyword_init: true)

    def initialize(params:, fetcher: Distillator::FetchCacheStore, guard: Distillator::FetchGuard)
      @params = (params || {}).to_h.with_indifferent_access
      @fetcher = fetcher
      @guard = guard
    end

    def call
      errors = validation_errors
      return failure(errors) if errors.any?

      fetch_result = fetcher.fetch(**fetch_params)
      Result.new(
        ok?: true,
        cache: fetch_result.respond_to?(:cache) ? fetch_result.cache : nil,
        message: fetch_kind,
        errors: [],
        fetch_result: fetch_result
      )
    end

    private

    attr_reader :params, :fetcher, :guard

    def validation_errors
      errors = []
      errors << "Fetch kind is invalid" unless VALID_KINDS.include?(fetch_kind)
      errors << "URI is invalid" unless valid_uri?
      errors << "URI is blocked" if errors.empty? && blocked_uri?
      errors
    end

    def failure(errors)
      Result.new(ok?: false, cache: nil, message: nil, errors: errors, fetch_result: nil)
    end

    def fetch_params
      {
        uri: uri,
        absolute_src: Distillator::BooleanParam.parse(params[:absolute_src]),
        include_fragment: include_fragment_value,
        force_scrape: force_scrape_value,
        force_scrape_every_hrs: force_scrape_every_hrs,
        use_phantomjs: use_phantomjs_value,
        json_post: json_post_value
      }
    end

    def fetch_kind
      params[:fetch_kind].presence || "normal"
    end

    def uri
      params[:uri].to_s.strip
    end

    def include_fragment_value
      return true if fetch_kind == "rendered"

      Distillator::BooleanParam.parse(params[:include_fragment])
    end

    def force_scrape_value
      return true if params[:force_scrape].nil?

      Distillator::BooleanParam.parse(params[:force_scrape])
    end

    def force_scrape_every_hrs
      value = params[:force_scrape_every_hrs]
      value.present? ? value : nil
    end

    def use_phantomjs_value
      fetch_kind == "rendered"
    end

    def json_post_value
      fetch_kind == "post"
    end

    def valid_uri?
      uri_key.normalized_url.present? && uri_key.normalized_url != "Error: not a URI"
    rescue Addressable::URI::InvalidURIError, URI::InvalidURIError
      false
    end

    def blocked_uri?
      !guard.check_url(uri_key.normalized_url).allowed?
    end

    def uri_key
      @uri_key ||= Distillator::WringerUrlKey.call(uri, include_fragment: include_fragment_value)
    end
  end
end
