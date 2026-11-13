# app/services/dsl/support/url_resolver.rb
module Dsl
  module Support
    class UrlResolver
    class << self
      def extract(value)
        return nil if value.nil?

        normalized = candidates(value).filter_map { |candidate| normalize_resolved_url(candidate) }
        valid = normalized.find { |url| valid_url?(url) }

        unless valid
          Rails.logger.debug { "[DSL] skipped invalid URL from #{value.inspect}" }
        end

        valid
      end

      private

      def candidates(value)
        case value
        when String
          [value] + json_string_candidates(value)
        when Array
          value
        else
          [value]
        end
      end

      def json_string_candidates(value)
        parsed = JSON.parse(value)

        case parsed
        when String
          [parsed]
        when Hash
          parsed.values.grep(String)
        when Array
          parsed.grep(String)
        else
          []
        end
      rescue JSON::ParserError
        []
      end

      def normalize_resolved_url(value)
        return nil if value.nil?

        url = normalize_url(value.to_s)
        return nil if url.blank?

        url
      end

      def normalize_url(url)
        ApplicationController.helpers.normalize_url(url)
      end

      def valid_url?(url)
        uri = URI.parse(url)
        uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::InvalidURIError
        false
      end
    end
    end
  end
end
