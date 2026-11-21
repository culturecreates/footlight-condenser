require "addressable/uri"
require "cgi"
require "uri"

module Distillator
  class WringerUrlKey
    Result = Struct.new(:uri_key, :normalized_url, keyword_init: true)

    def self.call(url, include_fragment: false)
      new(url, include_fragment: include_fragment).call
    end

    # Remote Wringer's validated_url decodes its input once before keying it.
    # Keep that compatibility behavior separate from native cache URL identity.
    def self.legacy(url, include_fragment: false)
      new(url, include_fragment: include_fragment, legacy_decode: true).call
    end

    def initialize(url, include_fragment: false, legacy_decode: false)
      @url = url
      @include_fragment = include_fragment
      @legacy_decode = legacy_decode
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

    attr_reader :url, :include_fragment, :legacy_decode

    def validated_url
      value = url.to_s.strip
      has_scheme = value.start_with?("http")
      value = CGI.unescape(value) if legacy_decode
      return value if has_scheme

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

      uri = legacy_decode ? Addressable::URI.parse(key) : URI.parse(key)
      raise URI::InvalidURIError, "Missing URL host: #{key}" if uri.host.blank?
    end

    def include_fragment?
      Distillator::BooleanParam.parse(include_fragment)
    end
  end
end
