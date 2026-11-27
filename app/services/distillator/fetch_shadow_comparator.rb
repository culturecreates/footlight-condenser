require "digest/sha2"
require "json"

module Distillator
  class FetchShadowComparator
    WRINGER_KEYS = %i[
      error_type
      received_404
      system_error
      unreachable
    ].freeze

    def self.compare(url:, legacy:, internal:, logger: Rails.logger)
      new(url: url, legacy: legacy, internal: internal, logger: logger).compare
    rescue StandardError => e
      logger.warn(
        event: "distillator.fetch_shadow.compare_error",
        url: url,
        error_class: e.class.name,
        error: e.message
      )
      nil
    end

    def initialize(url:, legacy:, internal:, logger:)
      @url = url
      @legacy = legacy || {}
      @internal = internal || {}
      @logger = logger || Rails.logger
    end

    def compare
      mismatches = comparable_keys.filter_map do |key|
        legacy_value = comparable(legacy).fetch(key)
        internal_value = comparable(internal).fetch(key)
        next if legacy_value == internal_value

        { field: key, legacy: legacy_value, internal: internal_value }
      end

      logger.info(
        event: "distillator.fetch_shadow.compare",
        url: url,
        matched: mismatches.empty?,
        mismatches: mismatches
      )

      mismatches
    rescue StandardError => e
      logger.warn(
        event: "distillator.fetch_shadow.compare_error",
        url: url,
        error_class: e.class.name,
        error: e.message
      )
      nil
    end

    private

    attr_reader :url, :legacy, :internal, :logger

    def comparable_keys
      comparable(legacy).keys
    end

    def comparable(response)
      {
        status: response[:status],
        body_hash: body_hash(response[:body]),
        headers: normalize_headers(response[:headers]),
        final_url: response[:final_url],
        redirect_chain: Array(response[:redirect_chain]).map(&:to_s),
        wringer_error_type: wringer_value(response, :error_type),
        wringer_received_404: wringer_value(response, :received_404),
        wringer_system_error: wringer_value(response, :system_error),
        wringer_unreachable: wringer_value(response, :unreachable)
      }
    end

    def body_hash(body)
      Digest::SHA256.hexdigest(JSON.generate(normalize_body(body)))
    rescue StandardError
      Digest::SHA256.hexdigest(body.to_s)
    end

    def normalize_body(value)
      case value
      when Hash
        value.sort_by { |key, _| key.to_s }.to_h { |key, child| [key.to_s, normalize_body(child)] }
      when Array
        value.map { |child| normalize_body(child) }
      else
        value
      end
    end

    def normalize_headers(headers)
      return {} unless headers.is_a?(Hash)

      headers.sort_by { |key, _| key.to_s }.to_h
    end

    def wringer_value(response, key)
      wringer = response[:wringer]
      return unless wringer.is_a?(Hash)

      wringer[key] || wringer[key.to_s]
    end
  end
end
