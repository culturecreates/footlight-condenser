module Distillator
  class CacheRefreshPreview
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(uri:, include_fragment: false, force_scrape: false, force_scrape_every_hrs: nil, fetch_kind: "normal", clock: Time.zone)
      @uri = uri
      @include_fragment = include_fragment
      @force_scrape = force_scrape
      @force_scrape_every_hrs = force_scrape_every_hrs
      @fetch_kind = fetch_kind
      @clock = clock
    end

    def call
      key = Distillator::WringerUrlKey.call(uri, include_fragment: include_fragment)
      return invalid_preview if key.normalized_url == "Error: not a URI"

      guard = Distillator::FetchGuard.check_url(key.normalized_url)
      return blocked_preview(key, guard) unless guard.allowed?

      cache = Distillator::FetchCache.find_by(uri_key: key.uri_key)
      build_preview(key, cache)
    rescue Addressable::URI::InvalidURIError, URI::InvalidURIError
      invalid_preview
    end

    private

    attr_reader :uri, :include_fragment, :force_scrape, :force_scrape_every_hrs, :fetch_kind, :clock

    def build_preview(key, cache)
      decision = Distillator::FetchCacheStore.refresh_decision(
        cache: cache,
        force_scrape: force_scrape,
        force_scrape_every_hrs: force_scrape_every_hrs,
        clock: clock
      )

      {
        uri_key: key.uri_key,
        normalized_url: key.normalized_url,
        cache_exists: cache.present?,
        cache_id: cache&.id,
        scrape_date: cache&.scrape_date,
        successful_refresh: cache&.successful_refresh,
        http_response_code: cache&.http_response_code,
        fetch_kind: fetch_kind,
        would_refresh: decision[:refresh],
        reason: decision[:reason]
      }
    end

    def blocked_preview(key, guard)
      {
        uri_key: key.uri_key,
        normalized_url: key.normalized_url,
        cache_exists: false,
        cache_id: nil,
        scrape_date: nil,
        successful_refresh: nil,
        http_response_code: nil,
        fetch_kind: fetch_kind,
        would_refresh: false,
        reason: :blocked_url,
        guard_reason: guard.reason,
        guard_error: guard.error
      }
    end

    def invalid_preview
      {
        uri_key: nil,
        normalized_url: nil,
        cache_exists: false,
        cache_id: nil,
        scrape_date: nil,
        successful_refresh: nil,
        http_response_code: nil,
        fetch_kind: fetch_kind,
        would_refresh: false,
        reason: :invalid_uri
      }
    end

    def now
      clock.now
    end
  end
end
