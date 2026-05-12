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

    def self.call(uri:, include_fragment: false, legacy_lookup: nil)
      new(uri: uri, include_fragment: include_fragment, legacy_lookup: legacy_lookup).call
    end

    def initialize(uri:, include_fragment: false, legacy_lookup: nil)
      @uri = uri
      @include_fragment = include_fragment
      @legacy_lookup = legacy_lookup
    end

    def call
      key = Distillator::WringerUrlKey.call(uri, include_fragment: include_fragment)
      legacy_result = fetch_legacy_cache(key.uri_key)
      legacy_cache = normalize_legacy_cache(legacy_result[:payload])
      distillator_cache = normalize_distillator_cache(Distillator::FetchCache.find_by(uri_key: key.uri_key))

      {
        uri: uri,
        uri_key: key.uri_key,
        legacy_cache: legacy_cache,
        legacy_source: legacy_result[:source],
        legacy_lookup_error: legacy_result[:error],
        distillator_cache: distillator_cache,
        distillator_source: "local_fetch_cache",
        diffs: build_diffs(legacy_cache, distillator_cache),
        missing: {
          legacy: legacy_cache.nil?,
          distillator: distillator_cache.nil?
        }
      }.then do |comparison|
        summary = build_summary(comparison)
        comparison.merge(summary: summary)
      end
    end

    private

    attr_reader :uri, :include_fragment, :legacy_lookup

    def fetch_legacy_cache(uri_key)
      return { payload: legacy_lookup.call(uri_key), source: "injected_lookup", error: nil } if legacy_lookup

      default_legacy_lookup(uri_key)
    end

    def default_legacy_lookup(uri_key)
      response = HTTParty.get(
        "#{ApplicationController.helpers.get_wringer_url_per_environment}/websites.json",
        query: { term: uri_key }
      )
      body = response.respond_to?(:body) ? response.body : response.to_s
      payload = JSON.parse(body)
      {
        payload: payload.is_a?(Array) ? payload.first : payload,
        source: "remote_wringer",
        error: nil
      }
    rescue StandardError => e
      {
        payload: nil,
        source: "unavailable",
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

    def normalize_distillator_cache(cache)
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

    def build_diffs(legacy_cache, distillator_cache)
      FIELDS.index_with do |field|
        legacy_value = comparable_value(legacy_cache, field)
        distillator_value = comparable_value(distillator_cache, field)
        {
          same: legacy_value == distillator_value,
          legacy: legacy_value,
          distillator: distillator_value,
          classification: classify_field(
            field,
            legacy_value: legacy_value,
            distillator_value: distillator_value,
            legacy_cache: legacy_cache,
            distillator_cache: distillator_cache
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
          !comparison.dig(:missing, :distillator) &&
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
