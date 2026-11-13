module Distillator
  class CacheWebsiteMatcher
    Result = Struct.new(:website, :matched_by, :warning, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(cache:, websites:)
      @cache = cache
      @websites = Array(websites)
    end

    def call
      matchers.each do |matcher|
        matches = matcher.resolver.call
        next if matches.empty?
        return Result.new(website: nil, matched_by: matcher.name, warning: "ambiguous_cache_match") if ambiguous?(matches)

        return Result.new(website: matches.first, matched_by: matcher.name, warning: matcher.warning)
      end

      Result.new(website: nil, matched_by: nil, warning: nil)
    end

    private

    Matcher = Struct.new(:name, :warning, :resolver, keyword_init: true)

    attr_reader :cache, :websites

    def matchers
      [
        Matcher.new(name: "webpage_url", warning: nil, resolver: -> { websites_for { |url| url.to_s == cache.normalized_url.to_s } }),
        Matcher.new(name: "uri_key", warning: nil, resolver: -> { websites_for { |url| url_key(url) == cache.uri_key.to_s } }),
        Matcher.new(name: "canonical_without_fragment", warning: nil, resolver: -> { websites_for { |url| canonical(url) == canonical(cache.normalized_url) } }),
        Matcher.new(name: "canonical_trailing_slash", warning: nil, resolver: -> { websites_for { |url| trailing_slash_normalized(url) == trailing_slash_normalized(cache.normalized_url) } }),
        Matcher.new(name: "final_url", warning: "final_url_redirect_match", resolver: -> { websites_for { |url| trailing_slash_normalized(url) == trailing_slash_normalized(cache.final_url) } })
      ]
    end

    def websites_for
      websites.select do |website|
        website.webpages.any? { |webpage| yield(webpage.url) }
      end
    end

    def ambiguous?(matches)
      matches.map(&:id).uniq.length > 1
    end

    def canonical(url)
      value = url.to_s
      value = value.split("#").first
      trailing_slash_normalized(value)
    end

    def trailing_slash_normalized(url)
      value = url.to_s.strip
      return value if value.blank?

      value.end_with?("/") ? value.chomp("/") : value
    end

    def url_key(url)
      Distillator::WringerUrlKey.call(url).uri_key
    rescue StandardError
      nil
    end
  end
end
