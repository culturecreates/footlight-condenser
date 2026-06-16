require "addressable/uri"
require "cgi"
require "uri"

module Distillator
  class WringerUrlKey
    Result = Struct.new(:uri_key, :normalized_url, keyword_init: true)

    def self.call(url, include_fragment: false)
      new(url, include_fragment: include_fragment).call
    end

    def initialize(url, include_fragment: false)
      @url = url
      @include_fragment = include_fragment
    end

    def call
      uri = Addressable::URI.parse(validated_url)
      key =
        if %w[http https].include?(uri.scheme)
          build_key(uri)
        else
          "Error: not a URI"
        end
      validate_key!(key)

      Result.new(uri_key: CGI.escape(key), normalized_url: key)
    end

    private

    attr_reader :url, :include_fragment

    def validated_url
      value = url.to_s.strip
      return value if value.start_with?("http")

      "http://#{value}"
    end

    def build_key(uri)
      key = "#{uri.scheme}://#{uri.host}"
      key += uri.path.to_s
      key += "?#{uri.query}" if uri.query
      key += "##{uri.fragment}" if include_fragment? && uri.fragment
      key
    end

    def validate_key!(key)
      return if key == "Error: not a URI"

      uri = URI.parse(key)
      raise URI::InvalidURIError, "Missing URL host: #{key}" if uri.host.blank?
    end

    def include_fragment?
      Distillator::BooleanParam.parse(include_fragment)
    end
  end
end
