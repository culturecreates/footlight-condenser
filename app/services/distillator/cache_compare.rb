require "digest"
require "json"

module Distillator
  class CacheCompare
    POLICIES = %i[operator strict].freeze
    BODY_DEPENDENT_FIELDS = %i[title html_sha256 html_bytes content_success final_url].freeze
    REVIEW_NEEDED_ENRICHMENT_FIELDS = %i[content_type final_url transport_success content_success].freeze
    OPERATOR_REVIEW_FIELDS = %i[html_sha256 html_bytes].freeze
    ALWAYS_BLOCKING_FIELDS = %i[title content_success transport_success blocking_issue cache_policy].freeze
    FIELDS = %i[
      title
      html_sha256
      html_bytes
      http_code
      content_type
      network_status
      transport_success
      content_success
      blocking_issue
      cache_policy
      signals
      hints
      final_url
      redirect_chain
      scrape_date
      successful_refresh
    ].freeze

    def self.call(uri:, include_fragment: false, legacy_lookup: nil, condenser_result: nil, wringer_endpoint: nil, comparison_policy: :operator)
      new(
        uri: uri,
        include_fragment: include_fragment,
        legacy_lookup: legacy_lookup,
        condenser_result: condenser_result,
        wringer_endpoint: wringer_endpoint,
        comparison_policy: comparison_policy
      ).call
    end

    def initialize(uri:, include_fragment: false, legacy_lookup: nil, condenser_result: nil, wringer_endpoint: nil, comparison_policy: :operator)
      @uri = uri
      @include_fragment = include_fragment
      @legacy_lookup = legacy_lookup
      @condenser_result = condenser_result
      @wringer_endpoint = wringer_endpoint
      @comparison_policy = normalize_policy(comparison_policy)
    end

    def call
      key = Distillator::WringerUrlKey.call(uri, include_fragment: include_fragment)
      legacy_result = fetch_legacy_cache(key)
      legacy_cache = normalize_legacy_cache(legacy_result)
      condenser_cache = normalize_condenser_cache(condenser_cache_record(key))

      {
        uri: uri,
        uri_key: key.uri_key,
        legacy_cache: legacy_cache,
        legacy_source: legacy_result[:source],
        legacy_lookup_status: legacy_result[:status],
        legacy_lookup_error: legacy_result[:error],
        condenser_cache: condenser_cache,
        condenser_source: "local_fetch_cache",
        comparison_policy: comparison_policy,
        diffs: build_diffs(legacy_cache, condenser_cache),
        missing: {
          legacy: legacy_cache.nil?,
          condenser: condenser_cache.nil?
        }
      }.then do |comparison|
        summary = build_summary(comparison)
        comparison
          .merge(summary: summary)
          .merge(
            distillator_cache: comparison[:condenser_cache],
            distillator_source: comparison[:condenser_source],
            missing: comparison[:missing].merge(distillator: comparison.dig(:missing, :condenser))
          )
      end
    end

    private

    attr_reader :uri, :include_fragment, :legacy_lookup, :condenser_result, :wringer_endpoint, :comparison_policy

    def condenser_cache_record(key)
      condenser_result&.cache || Distillator::FetchCache.find_by(uri_key: key.uri_key)
    end

    def fetch_legacy_cache(key)
      if legacy_lookup
        payload = legacy_lookup.call(key.uri_key)
        return { payload: payload, source: "injected_lookup", status: payload.present? ? "ok" : "missing", error: nil }
      end

      default_legacy_lookup(key)
    end

    def default_legacy_lookup(key)
      endpoint = wringer_endpoint || Distillator::WringerEndpoint.current
      unless endpoint.legacy_lookup_base_url.present?
        return {
          payload: nil,
          source: "missing_config",
          status: "missing_config",
          error: "missing_config"
        }
      end

      payload = first_payload(
        HTTParty.get(
          "#{endpoint.legacy_lookup_base_url}/websites.json",
          query: { term: key.uri_key }
        )
      )
      return { payload: nil, source: "remote_wringer", status: "missing", error: nil } if payload.blank?

      if payload["html"].present? || payload[:html].present?
        return {
          payload: payload,
          source: "remote_wringer",
          status: "ok",
          error: nil
        }
      end

      hydrated_payload = hydrate_legacy_body(
        endpoint: endpoint,
        normalized_url: key.normalized_url,
        payload: payload
      )
      return hydrated_payload if hydrated_payload.is_a?(Hash) && hydrated_payload.key?(:status)

      hydrated_html_present = hydrated_payload.present? && (hydrated_payload["html"].present? || hydrated_payload[:html].present?)
      {
        payload: hydrated_payload || payload,
        source: "remote_wringer",
        status: hydrated_html_present ? "ok" : "body_omitted",
        error: hydrated_html_present ? nil : "legacy_body_omitted"
      }
    rescue StandardError => e
      {
        payload: nil,
        source: "remote_wringer",
        status: "unreachable",
        error: e.message
      }
    end

    def normalize_legacy_cache(result)
      payload = result[:payload]
      return nil if payload.blank?

      data = payload.with_indifferent_access
      {
        html: data[:html],
        title: extract_title(data[:html]).presence || data[:title].presence || data[:name].presence || data[:page_name].presence,
        scrape_date: data[:scrape_date],
        successful_refresh: data[:successful_refresh],
        http_code: data[:http_code] || data[:http_response_code],
        content_type: signal_value(data[:signals], :content_type),
        network_status: signal_value(data[:signals], :network_status),
        transport_success: signal_value(data[:signals], :transport_success),
        content_success: signal_value(data[:signals], :content_success),
        blocking_issue: signal_value(data[:signals], :blocking_issue_key) || signal_value(data[:signals], :primary_issue_key),
        cache_policy: data[:cache],
        signals: (data[:signals] || {}).to_h,
        hints: Array(data[:hints]),
        final_url: data[:final_url],
        redirect_chain: Array(data[:redirect_chain]),
        body_hydrated: data[:html].present?,
        lookup_status: result[:status]
      }
    end

    def normalize_condenser_cache(cache)
      return nil unless cache

      {
        html: cache.html,
        title: extract_title(cache.html),
        scrape_date: cache.scrape_date,
        successful_refresh: cache.successful_refresh,
        http_code: cache.http_response_code,
        content_type: cache.signals.to_h["content_type"],
        network_status: cache.signals.to_h["network_status"],
        transport_success: cache.signals.to_h["transport_success"],
        content_success: cache.signals.to_h["content_success"],
        blocking_issue: cache.signals.to_h["blocking_issue_key"] || cache.signals.to_h["primary_issue_key"],
        cache_policy: cache.signals.to_h["cache"],
        signals: (cache.signals || {}).to_h,
        hints: Array(cache.hints),
        final_url: cache.final_url,
        redirect_chain: Array(cache.redirect_chain)
      }
    end

    def build_diffs(legacy_cache, condenser_cache)
      FIELDS.index_with do |field|
        legacy_value = comparable_value(legacy_cache, field)
        condenser_value = comparable_value(condenser_cache, field)
        {
          same: legacy_value == condenser_value,
          legacy: legacy_value,
          condenser: condenser_value,
          distillator: condenser_value,
          classification: classify_field(
            field,
            legacy_value: legacy_value,
            distillator_value: condenser_value,
            legacy_cache: legacy_cache,
            distillator_cache: condenser_cache
          )
        }
      end
    end

    def build_summary(comparison)
      diffs = comparison[:diffs]
      changed = diffs.select { |_field, diff| !diff[:same] }
      blocking = changed.select { |_field, diff| diff[:classification] == :blocking_regression }.keys
      improvements = changed.select { |_field, diff| diff[:classification] == :distillator_improvement }.keys
      metadata_only = changed.select { |_field, diff| diff[:classification] == :metadata_only }.keys
      unknown = changed.select { |_field, diff| diff[:classification] == :unknown }.keys
      review_needed = changed.select { |_field, diff| diff[:classification] == :review_needed }.keys

      {
        same: changed.empty?,
        promotable: !comparison.dig(:missing, :legacy) &&
          !comparison.dig(:missing, :condenser) &&
          comparison[:legacy_lookup_status] == "ok" &&
          blocking.empty? &&
          review_needed.empty? &&
          unknown.empty?,
        outcome: comparison_outcome(comparison, blocking: blocking, review_needed: review_needed, unknown: unknown, metadata_only: metadata_only),
        primary_reason: comparison_primary_reason(comparison, blocking: blocking, review_needed: review_needed, unknown: unknown, metadata_only: metadata_only),
        blocking_regressions: blocking,
        improvements: improvements,
        metadata_only_diffs: metadata_only,
        review_needed_diffs: review_needed,
        unknown_diffs: unknown,
        http_code_difference: !diffs.dig(:http_code, :same),
        final_url_difference: !diffs.dig(:final_url, :same),
        content_type_difference: !diffs.dig(:content_type, :same),
        html_hash_difference: !diffs.dig(:html_sha256, :same),
        body_byte_difference: !diffs.dig(:html_bytes, :same),
        title_difference: !diffs.dig(:title, :same)
      }
    end

    def comparable_value(cache, field)
      return nil unless cache

      case field
      when :html_sha256
        Digest::SHA256.hexdigest(cache[:html].to_s)
      when :html_bytes
        cache[:html].to_s.bytesize
      else
        cache[field]
      end
    end

    def classify_field(field, legacy_value:, distillator_value:, legacy_cache:, distillator_cache:)
      return :metadata_only if legacy_value == distillator_value
      return :blocking_regression if distillator_cache.nil?
      return :unknown if legacy_cache.nil?
      return :unknown if legacy_body_unavailable?(legacy_cache) && BODY_DEPENDENT_FIELDS.include?(field)
      return :review_needed if operator_review_only?(field)
      return :review_needed if review_needed_enrichment?(field, legacy_value, distillator_value)
      return :review_needed if safe_default_final_url?(field, legacy_value, distillator_value)

      case field
      when *ALWAYS_BLOCKING_FIELDS
        :blocking_regression
      when :final_url, :content_type, :http_code
        operator_metadata_difference?(field, legacy_value, distillator_value) ? :review_needed : :blocking_regression
      when :html_sha256, :html_bytes
        strict_policy? ? :blocking_regression : :review_needed
      when :scrape_date, :successful_refresh, :redirect_chain, :network_status, :signals, :hints
        if legacy_value.nil? && distillator_value.present?
          :distillator_improvement
        else
          :metadata_only
        end
      else
        :unknown
      end
    end

    def extract_title(html)
      html.to_s[%r{<title>(.*?)</title>}im, 1].to_s.strip.presence
    end

    def signal_value(signals, key)
      return nil unless signals.respond_to?(:to_h)

      data = signals.to_h
      data[key.to_s] || data[key.to_sym]
    end

    def first_payload(response)
      body = response.respond_to?(:body) ? response.body : response.to_s
      payload = JSON.parse(body)
      payload.is_a?(Array) ? payload.first : payload
    end

    def hydrate_legacy_body(endpoint:, normalized_url:, payload:)
      return nil unless endpoint.compatibility_base_url.present?

      # This endpoint is expected to return Wringer-compatible cached output only.
      # CacheCompare keeps the comparison path read-only by sending only the URI
      # and never force_scrape/use_phantomjs/json_post flags during hydration.
      hydrated_payload = first_payload(
        HTTParty.get(
          "#{endpoint.compatibility_base_url}/websites/wring.json",
          query: hydration_query(normalized_url)
        )
      )
      return nil if hydrated_payload.blank?

      payload.merge(hydrated_payload)
    rescue StandardError => e
      {
        payload: payload,
        source: "remote_wringer",
        status: "unreachable",
        error: e.message
      }
    end

    def legacy_body_unavailable?(legacy_cache)
      legacy_cache[:body_hydrated] == false || legacy_cache[:lookup_status] == "body_omitted"
    end

    def review_needed_enrichment?(field, legacy_value, distillator_value)
      REVIEW_NEEDED_ENRICHMENT_FIELDS.include?(field) &&
        legacy_unknown?(legacy_value) &&
        distillator_value.present?
    end

    def operator_review_only?(field)
      operator_policy? && OPERATOR_REVIEW_FIELDS.include?(field)
    end

    def safe_default_final_url?(field, legacy_value, distillator_value)
      field == :final_url &&
        legacy_unknown?(legacy_value) &&
        distillator_value.to_s == normalized_url
    end

    def operator_metadata_difference?(field, legacy_value, distillator_value)
      return false unless operator_policy?

      case field
      when :content_type
        legacy_unknown?(legacy_value) && distillator_value.to_s == "html"
      when :http_code
        successful_http?(legacy_value) && successful_http?(distillator_value)
      when :final_url
        legacy_unknown?(legacy_value) && distillator_value.present?
      else
        false
      end
    end

    def legacy_unknown?(value)
      value.nil? || value.to_s.strip.blank? || value.to_s == "unknown"
    end

    def successful_http?(value)
      value.to_i >= 200 && value.to_i < 300
    end

    def hydration_query(normalized_url)
      { uri: normalized_url }
    end

    def normalized_url
      @normalized_url ||= Distillator::WringerUrlKey.call(uri, include_fragment: include_fragment).normalized_url
    end

    def operator_policy?
      comparison_policy == :operator
    end

    def strict_policy?
      comparison_policy == :strict
    end

    def normalize_policy(value)
      candidate = value.to_s.presence&.to_sym || :operator
      POLICIES.include?(candidate) ? candidate : :operator
    end

    def comparison_outcome(comparison, blocking:, review_needed:, unknown:, metadata_only:)
      return "blocked" if comparison.dig(:missing, :condenser) || blocking.any?
      return "unknown" if comparison.dig(:missing, :legacy) || comparison[:legacy_lookup_status] != "ok" || unknown.any?
      return "review" if review_needed.any?
      return "ready_with_metadata_notes" if metadata_only.any?

      "pass"
    end

    def comparison_primary_reason(comparison, blocking:, review_needed:, unknown:, metadata_only:)
      return "Condenser cache missing." if comparison.dig(:missing, :condenser)
      return "Legacy cache missing." if comparison.dig(:missing, :legacy)
      return "Legacy Wringer body was omitted from the comparison endpoint." if comparison[:legacy_lookup_status] == "body_omitted"
      return "Safety blockers: #{blocking.join(', ')}" if blocking.any?
      return "Some legacy comparison fields were unavailable." if unknown.any?
      return "Needs review: #{review_needed.join(', ')}" if review_needed.any?
      return "Metadata notes: #{metadata_only.join(', ')}" if metadata_only.any?

      "Wringer and Condenser match on the compared fields."
    end
  end
end
