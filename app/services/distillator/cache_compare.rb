require "digest"
require "json"
require "time"

module Distillator
  class CacheCompare
    POLICIES = %i[operator strict].freeze
    BODY_DEPENDENT_FIELDS = %i[title html_sha256 html_bytes content_success final_url].freeze
    OBSERVATION_FIELDS = %i[content_type final_url transport_success content_success http_code cache_policy].freeze
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

    def self.call(uri:, include_fragment: false, legacy_lookup: nil, condenser_result: nil, wringer_endpoint: nil, comparison_policy: :operator, fresh_legacy: false, render_js: false)
      new(
        uri: uri,
        include_fragment: include_fragment,
        legacy_lookup: legacy_lookup,
        condenser_result: condenser_result,
        wringer_endpoint: wringer_endpoint,
        comparison_policy: comparison_policy,
        fresh_legacy: fresh_legacy,
        render_js: render_js
      ).call
    end

    def initialize(uri:, include_fragment: false, legacy_lookup: nil, condenser_result: nil, wringer_endpoint: nil, comparison_policy: :operator, fresh_legacy: false, render_js: false)
      @uri = uri
      @include_fragment = include_fragment
      @legacy_lookup = legacy_lookup
      @condenser_result = condenser_result
      @wringer_endpoint = wringer_endpoint
      @comparison_policy = normalize_policy(comparison_policy)
      @fresh_legacy = fresh_legacy
      @render_js = render_js
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
        legacy_fetch: legacy_result[:fetch],
        condenser_cache: condenser_cache,
        condenser_source: @fresh_legacy ? (@render_js ? "fresh_rendered_fetch" : "fresh_native_fetch") : "local_fetch_cache",
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
      if @fresh_legacy
        return nil unless condenser_result && condenser_result.cache_hit != true &&
          condenser_result.transport_success? && condenser_result.content_success?

        return condenser_result.cache
      end
      condenser_result&.cache || Distillator::FetchCache.find_by(uri_key: key.uri_key)
    end

    def fetch_legacy_cache(key)
      if @fresh_legacy
        return Distillator::FreshWringerSnapshot.call(uri: key.normalized_url, render_js: @render_js,
          include_fragment: include_fragment, wringer_endpoint: wringer_endpoint)
      end
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
        title: Distillator::HtmlContent.title(data[:html], headers: data[:headers].to_h) ||
          Distillator::HtmlContent.normalize_text(data[:title].presence || data[:name].presence || data[:page_name]).presence,
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
        redirect_chain: Array(cache.redirect_chain),
        operational_failed: Distillator::TransitionStatus.cache_fetch_failed?(cache)
      }
    end

    def build_diffs(legacy_cache, condenser_cache)
      FIELDS.index_with do |field|
        legacy_value = comparable_value(legacy_cache, field)
        condenser_value = comparable_value(condenser_cache, field)
        same = equivalent_values?(field, legacy_value, condenser_value, legacy_cache, condenser_cache)
        {
          same: same,
          legacy: legacy_value,
          condenser: condenser_value,
          distillator: condenser_value,
          classification: same ? :metadata_only : classify_field(
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
      operational_failures = operational_failures(comparison[:condenser_cache])

      {
        same: changed.empty?,
        promotable: !comparison.dig(:missing, :legacy) &&
          !comparison.dig(:missing, :condenser) &&
          comparison[:legacy_lookup_status] == "ok" &&
          operational_failures.empty? &&
          blocking.empty? &&
          review_needed.empty? &&
          unknown.empty?,
        outcome: comparison_outcome(comparison, blocking: blocking + operational_failures, review_needed: review_needed, unknown: unknown, metadata_only: metadata_only + improvements),
        primary_reason: comparison_primary_reason(comparison, blocking: blocking, review_needed: review_needed, unknown: unknown, metadata_only: metadata_only,
          operational_failures: operational_failures, improvements: improvements),
        operational_failures: operational_failures,
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

    def equivalent_values?(field, legacy_value, condenser_value, legacy_cache, condenser_cache)
      return true if legacy_value == condenser_value

      case field
      when :scrape_date, :successful_refresh
        legacy_time = comparison_timestamp(legacy_value)
        condenser_time = comparison_timestamp(condenser_value)
        return false unless legacy_time && condenser_time

        # An ISO timestamp without fractions cannot establish subsecond drift.
        precision = [timestamp_precision(legacy_value), timestamp_precision(condenser_value)].min
        scale = 10**precision
        (legacy_time.to_r * scale).floor == (condenser_time.to_r * scale).floor
      when :redirect_chain
        redirect_destinations(legacy_cache) == redirect_destinations(condenser_cache)
      else
        false
      end
    end

    def comparison_timestamp(value)
      return value.to_time if value.is_a?(Time) || value.is_a?(DateTime) || value.is_a?(ActiveSupport::TimeWithZone)
      return nil unless value.is_a?(String) && value.match?(/(?:Z|[+-]\d{2}:?\d{2})\z/i)

      Time.iso8601(value)
    rescue ArgumentError, TypeError
      nil
    end

    def timestamp_precision(value)
      value.is_a?(String) ? [value[/\.([0-9]+)/, 1].to_s.length, 9].min : 9
    end

    def redirect_destinations(cache)
      return nil unless cache

      chain = Array(cache[:redirect_chain])
      return chain unless chain.first == normalized_url
      # Preserve inconsistent singleton records and self-redirect evidence.
      if chain.length == 1
        return chain if cache[:final_url].present? && cache[:final_url] != normalized_url
        return chain if Distillator::BooleanParam.parse(signal_value(cache[:signals], :redirected))
      end
      chain.drop(1)
    end

    def classify_field(field, legacy_value:, distillator_value:, legacy_cache:, distillator_cache:)
      return :metadata_only if legacy_value == distillator_value
      return :blocking_regression if distillator_cache.nil?
      return :unknown if legacy_cache.nil?
      return :unknown if legacy_body_unavailable?(legacy_cache) && BODY_DEPENDENT_FIELDS.include?(field)
      # A missing legacy observation is not evidence that Condenser changed
      # behavior. Assess actual current failures independently of field diffs.
      if OBSERVATION_FIELDS.include?(field) && legacy_unknown?(legacy_value)
        return :metadata_only if legacy_unknown?(distillator_value)
        # An observed failure still blocks through operational_failures; absent
        # legacy telemetry cannot establish that the failure is a regression.
        return :distillator_improvement
      end

      case field
      when :title, :cache_policy
        :blocking_regression
      when :transport_success, :content_success
        return :unknown if legacy_unknown?(distillator_value)
        Distillator::BooleanParam.parse(distillator_value) ? :distillator_improvement : :blocking_regression
      when :blocking_issue
        operational_failures(distillator_cache).any? ? :blocking_regression : :metadata_only
      when :final_url, :content_type, :http_code
        return :metadata_only if field == :http_code && successful_http?(legacy_value) && successful_http?(distillator_value)
        operator_policy? && field == :final_url ? :review_needed : :blocking_regression
      when :html_sha256, :html_bytes
        # Raw HTML drift remains visible; selected DSL values establish data
        # parity. Hash/byte equality is not an activation requirement.
        :metadata_only
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
      Distillator::HtmlContent.title(html)
    end

    def signal_value(signals, key)
      return nil unless signals.respond_to?(:to_h)

      data = signals.to_h
      data.key?(key.to_s) ? data[key.to_s] : data[key.to_sym]
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

    def operational_failures(cache)
      return [] unless cache

      failures = []
      failures << :http_code if cache[:http_code].present? && !successful_http?(cache[:http_code])
      %i[transport_success content_success].each do |field|
        failures << field if !legacy_unknown?(cache[field]) && !Distillator::BooleanParam.parse(cache[field])
      end
      failures << :blocking_issue if cache[:signals].to_h["blocking_issue_key"].present?
      failures << :fetch_health if cache[:operational_failed]
      failures << :empty_html if cache[:html].blank?
      failures.uniq
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

    def comparison_primary_reason(comparison, blocking:, review_needed:, unknown:, metadata_only:, operational_failures:, improvements:)
      return "Condenser cache missing." if comparison.dig(:missing, :condenser)
      return "Condenser fetch safety failures: #{operational_failures.join(', ')}" if operational_failures.any?
      return "Legacy cache missing." if comparison.dig(:missing, :legacy)
      return "Legacy Wringer body was omitted from the comparison endpoint." if comparison[:legacy_lookup_status] == "body_omitted"
      return "Safety blockers: #{blocking.join(', ')}" if blocking.any?
      return "Some legacy comparison fields were unavailable." if unknown.any?
      return "Needs review: #{review_needed.join(', ')}" if review_needed.any?
      return "Additional Condenser diagnostics: #{improvements.join(', ')}" if improvements.any?
      return "Metadata notes: #{metadata_only.join(', ')}" if metadata_only.any?

      "Wringer and Condenser match on the compared fields."
    end
  end
end
