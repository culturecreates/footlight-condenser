require "digest/sha1"
require "json"

module Distillator
  class FetchReplay
    REQUIRED_RESPONSE_KEYS = %w[
      status
      body
      headers
      final_url
      redirect_chain
      wringer
    ].freeze
    OPTIONAL_RESPONSE_KEYS = %w[duration_ms].freeze
    ALLOWED_RESPONSE_KEYS = (REQUIRED_RESPONSE_KEYS + OPTIONAL_RESPONSE_KEYS).freeze

    def self.load(url:)
      return unless ENV["REPLAY_FETCH"].present?

      site = sanitize_site(ENV["FETCH_SITE"])
      digest = Digest::SHA1.hexdigest(url.to_s)
      path = Rails.root.join("data", "migration_fixtures", site, "fetch", "#{digest}.json")
      raise "Missing replay fixture for URL: #{url}" unless File.exist?(path)

      payload = parse_fixture(path: path, url: url)
      validate_payload!(payload, path: path, url: url)
      response = payload.fetch("response")
      validate_response!(response, path: path, url: url)
      normalized = normalize_response(response)

      if ENV["EXPORT_DEBUG"].present?
        body = normalized[:body]
        body_size =
          case body
          when String
            body.bytesize
          when Array, Hash
            body.size
          when nil
            0
          else
            body.to_s.bytesize
          end
        body_present = !(body.respond_to?(:empty?) ? body.empty? : body.nil?)

        Rails.logger.warn(
          "[EXPORT_DEBUG] FetchReplay.load site=#{site} url=#{url} fixture=#{path} " \
          "status=#{normalized[:status].inspect} body_present=#{body_present} body_size=#{body_size}"
        )
      end

      normalized
    end

    def self.parse_fixture(path:, url:)
      JSON.parse(File.read(path))
    rescue StandardError => e
      raise "#{fixture_context(path: path, url: url)} invalid JSON: #{e.message}"
    end
    private_class_method :parse_fixture

    def self.validate_payload!(payload, path:, url:)
      unless payload.is_a?(Hash)
        raise "#{fixture_context(path: path, url: url)} must contain a JSON object"
      end

      missing = []
      missing << "url" unless payload.key?("url")
      missing << "response" unless payload.key?("response")
      raise "#{fixture_context(path: path, url: url)} missing #{missing.join(', ')}" if missing.any?

      return if payload["url"].to_s == url.to_s

      raise "#{fixture_context(path: path, url: url)} URL mismatch: #{payload['url']}"
    end
    private_class_method :validate_payload!

    def self.validate_response!(response, path:, url:)
      unless response.is_a?(Hash)
        raise "#{fixture_context(path: path, url: url)} response must be a JSON object"
      end

      missing = REQUIRED_RESPONSE_KEYS - response.keys.map(&:to_s)
      extra = response.keys.map(&:to_s) - ALLOWED_RESPONSE_KEYS

      problems = []
      problems << "missing #{missing.join(', ')}" if missing.any?
      problems << "unexpected #{extra.join(', ')}" if extra.any?
      return if problems.empty?

      raise "#{fixture_context(path: path, url: url)} invalid response contract: #{problems.join('; ')}"
    end
    private_class_method :validate_response!

    def self.normalize_response(response)
      symbolized = deep_symbolize(response)
      {
        status: normalize_status(symbolized[:status]),
        body: symbolized[:body],
        headers: normalize_headers(response["headers"] || response[:headers]),
        final_url: symbolized[:final_url],
        redirect_chain: Array(symbolized[:redirect_chain]).map(&:to_s),
        wringer: symbolized[:wringer],
        duration_ms: symbolized[:duration_ms].nil? ? 0 : symbolized[:duration_ms]
      }
    end
    private_class_method :normalize_response

    def self.normalize_status(status)
      return status if status.is_a?(Symbol)
      return status.delete_prefix(":").to_sym if status.is_a?(String)

      status
    end
    private_class_method :normalize_status

    def self.normalize_headers(headers)
      return {} unless headers.is_a?(Hash)

      headers.each_with_object({}) do |(key, value), out|
        out[normalize_header_key(key)] = deep_symbolize(value)
      end
    end
    private_class_method :normalize_headers

    def self.normalize_header_key(key)
      key.to_s
         .strip
         .downcase
         .tr("-", "_")
         .gsub(/[^a-z0-9_]+/, "_")
         .gsub(/\A_+|_+\z/, "")
         .to_sym
    end
    private_class_method :normalize_header_key

    def self.deep_symbolize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, val), out|
          symbol_key = key.respond_to?(:to_sym) ? key.to_sym : key
          out[symbol_key] = deep_symbolize(val)
        end
      when Array
        value.map { |item| deep_symbolize(item) }
      else
        value
      end
    end
    private_class_method :deep_symbolize

    def self.sanitize_site(raw)
      value = raw.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      value.present? ? value : "default"
    end
    private_class_method :sanitize_site

    def self.fixture_context(path:, url:)
      "Replay fixture #{path} for URL #{url}"
    end
    private_class_method :fixture_context
  end
end
