module Distillator
  class FetchCacheCompatSerializer
    def initialize(cache)
      @cache = cache
    end

    def as_json(*)
      health_status = cache.respond_to?(:health_status) ? cache.health_status.presence : nil
      health_severity = cache.respond_to?(:health_severity) ? cache.health_severity.presence : nil
      health_reasons = cache.respond_to?(:health_reasons) ? Array(cache.health_reasons).presence : nil
      health = health_status.present? ? nil : Distillator::CacheHealth.call(cache)

      {
        id: cache.id,
        uri: cache.uri_key,
        uri_key: cache.uri_key,
        normalized_url: cache.normalized_url,
        name: cache.name,
        scrape_date: cache.scrape_date,
        successful_refresh: cache.successful_refresh,
        http_response_code: cache.http_response_code,
        has_html: cache.html.present?,
        html_bytes: cache.respond_to?(:html_bytes) ? cache.html_bytes.to_i : cache.html.to_s.bytesize,
        body_bytes: cache.respond_to?(:body_bytes) ? cache.body_bytes.to_i : cache.body.to_s.bytesize,
        signals: cache.signals || {},
        hints: cache.hints || [],
        network_status: cache.respond_to?(:network_status) ? cache.network_status.presence || signal(:network_status) : signal(:network_status),
        content_type: cache.respond_to?(:content_type) ? cache.content_type.presence || signal(:content_type) : signal(:content_type),
        redirect_type: signal(:redirect_type),
        fetch_path: signal(:fetch_path),
        native_ineligible_reason: signal(:native_ineligible_reason),
        final_url: cache.final_url,
        redirect_chain: cache.redirect_chain || [],
        health_status: health_status || health.status.to_s,
        health_label: health ? health.label : Distillator::CacheHealth::STATUS_META.fetch(health_status.to_sym, Distillator::CacheHealth::STATUS_META[:unknown]).fetch(:label),
        health_severity: health_severity || health.severity,
        health_reasons: health_reasons || health.reasons,
        created_at: cache.created_at,
        updated_at: cache.updated_at
      }
    end

    private

    attr_reader :cache

    def signal(key)
      signals = (cache.signals || {}).to_h
      signals[key.to_s] || signals[key.to_sym]
    end
  end
end
