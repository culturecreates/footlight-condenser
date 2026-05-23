require "cgi"
require "digest"
require "json"

module Distillator
  class CacheCompare
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

    def self.call(uri:, include_fragment: false, legacy_lookup: nil, condenser_result: nil, wringer_endpoint: nil)
      new(
        uri: uri,
        include_fragment: include_fragment,
        legacy_lookup: legacy_lookup,
        condenser_result: condenser_result,
        wringer_endpoint: wringer_endpoint
      ).call
    end

    def initialize(uri:, include_fragment: false, legacy_lookup: nil, condenser_result: nil, wringer_endpoint: nil)
      @uri = uri
      @include_fragment = include_fragment
      @legacy_lookup = legacy_lookup
      @condenser_result = condenser_result
      @wringer_endpoint = wringer_endpoint
    end

    def call
      key = Distillator::WringerUrlKey.call(uri, include_fragment: include_fragment)
      legacy_result = fetch_legacy_cache(key.uri_key)
      legacy_cache = normalize_legacy_cache(legacy_result[:payload])
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

    attr_reader :uri, :include_fragment, :legacy_lookup, :condenser_result, :wringer_endpoint

    def condenser_cache_record(key)
      condenser_result&.cache || Distillator::FetchCache.find_by(uri_key: key.uri_key)
    end

    def fetch_legacy_cache(uri_key)
      if legacy_lookup
        payload = legacy_lookup.call(uri_key)
        return { payload: payload, source: "injected_lookup", status: payload.present? ? "ok" : "missing", error: nil }
      end

      default_legacy_lookup(uri_key)
    end

    def default_legacy_lookup(uri_key)
      endpoint = wringer_endpoint || Distillator::WringerEndpoint.current
      unless endpoint.legacy_lookup_base_url.present?
        return {
          payload: nil,
          source: "missing_config",
          status: "missing_config",
          error: "missing_config"
        }
      end

      response = HTTParty.get(
        "#{endpoint.legacy_lookup_base_url}/websites.json",
        query: { term: uri_key }
      )
      body = response.respond_to?(:body) ? response.body : response.to_s
      payload = JSON.parse(body)
      {
        payload: payload.is_a?(Array) ? payload.first : payload,
        source: "remote_wringer",
        status: "ok",
        error: nil
      }
    rescue StandardError => e
      {
        payload: nil,
        source: "remote_wringer",
        status: "unreachable",
        error: e.message
      }
    end

    def normalize_legacy_cache(payload)
      return nil if payload.blank?

      data = payload.with_indifferent_access
      {
        html: data[:html],
        title: extract_title(data[:html]),
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
        redirect_chain: Array(data[:redirect_chain])
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

      {
        same: changed.empty?,
        promotable: !comparison.dig(:missing, :legacy) &&
          !comparison.dig(:missing, :condenser) &&
          blocking.empty?,
        blocking_regressions: blocking,
        improvements: improvements,
        metadata_only_diffs: metadata_only,
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

      case field
      when :html_sha256, :http_code, :final_url, :content_type, :content_success, :transport_success, :blocking_issue, :cache_policy
        :blocking_regression
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
      html.to_s[/\<title\>(.*?)\<\/title\>/im, 1].to_s.strip.presence
    end

    def signal_value(signals, key)
      return nil unless signals.respond_to?(:to_h)

      data = signals.to_h
      data[key.to_s] || data[key.to_sym]
    end
  end
end
