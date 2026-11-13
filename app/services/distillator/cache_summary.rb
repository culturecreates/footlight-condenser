module Distillator
  class CacheSummary
    CARD_DEFINITIONS = [
      { key: :total, label: "Total", params: {} },
      { key: :healthy, label: "Healthy", params: { health: "healthy" } },
      { key: :preserved_after_failure, label: "Preserved after failure", params: { health: "preserved_after_failure" } },
      { key: :never_fetched, label: "Never fetched", params: { health: "never_fetched" } },
      { key: :network_failed, label: "Network failed", params: { health: "network_failed" } },
      { key: :blocked, label: "Blocked", params: { health: "blocked" } },
      { key: :empty_body, label: "Empty body", params: { health: "empty_body" } },
      { key: :missing_html, label: "Missing HTML", params: { has_html: "false" } },
      { key: :status_4xx, label: "4xx", params: { status_group: "4xx" } },
      { key: :status_5xx, label: "5xx", params: { status_group: "5xx" } },
      { key: :redirected, label: "Redirected", params: { redirected: "true" } },
      { key: :json_detected, label: "JSON detected", params: { content_type: "json" } },
      { key: :stale, label: "Stale", params: { health: "stale" } }
    ].freeze

    def self.call(caches: nil, scope: nil)
      new(caches: caches, scope: scope).call
    end

    def initialize(caches: nil, scope: nil)
      @caches = caches
      @scope = scope
    end

    def call
      CARD_DEFINITIONS.map do |definition|
        {
          key: definition.fetch(:key),
          label: definition.fetch(:label),
          count: count_for(definition.fetch(:key)),
          params: definition.fetch(:params)
        }
      end
    end

    private

    attr_reader :caches, :scope

    def count_for(key)
      case key
      when :total
        count_total
      when :healthy, :preserved_after_failure, :never_fetched, :network_failed, :blocked, :empty_body, :stale
        count_health_status(key)
      when :missing_html
        count_missing_html
      when :status_4xx
        count_status_group(400..499)
      when :status_5xx
        count_status_group(500..599)
      when :redirected
        count_redirected
      when :json_detected
        count_json_detected
      else
        0
      end
    end

    def enumerable_caches
      @enumerable_caches ||= Array(caches || relation_scope&.to_a || [])
    end

    def relation_scope
      scope if scope.is_a?(ActiveRecord::Relation)
    end

    def materialized_fields_available?
      relation_scope && Distillator::FetchCache.column_names.include?("health_status")
    end

    def count_health_status(status)
      return relation_scope.where(health_status: status.to_s).count if materialized_fields_available?

      enumerable_caches.count { |cache| health(cache).status == status }
    end

    def count_total
      return relation_scope.count if relation_scope

      enumerable_caches.length
    end

    def count_missing_html
      return relation_scope.where(html: [nil, ""]).count if relation_scope

      enumerable_caches.count { |cache| cache.html.blank? }
    end

    def count_status_group(range)
      return relation_scope.where(http_response_code: range).count if relation_scope

      enumerable_caches.count { |cache| cache.http_response_code.to_i.in?(range) }
    end

    def count_redirected
      if relation_scope
        return relation_scope.where(redirected: true).count if materialized_fields_available?
        return relation_scope.where("jsonb_array_length(redirect_chain) > 0 OR (final_url IS NOT NULL AND final_url <> normalized_url)").count
      end

      enumerable_caches.count { |cache| redirected?(cache) }
    end

    def count_json_detected
      if relation_scope
        return relation_scope.where(content_type: "json").count if materialized_fields_available?
        return relation_scope.where("COALESCE(signals ->> 'content_type', 'unknown') = ?", "json").count
      end

      enumerable_caches.count { |cache| content_type(cache) == "json" }
    end

    def health(cache)
      Distillator::CacheHealth.call(cache)
    end

    def redirected?(cache)
      Array(cache.redirect_chain).any? || cache.final_url.to_s.present? && cache.final_url.to_s != cache.normalized_url.to_s
    end

    def content_type(cache)
      signals = (cache.signals || {}).to_h
      signals["content_type"] || signals[:content_type] || "unknown"
    end
  end
end
