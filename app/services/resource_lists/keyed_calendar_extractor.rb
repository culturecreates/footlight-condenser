# frozen_string_literal: true

require "nokogiri"
require "uri"

module ResourceLists
  # Extracts URL/key pairs from one fetched calendar HTML document.
  # XPath expressions for URL and key are evaluated relative to the same card;
  # this prevents accidental positional joins between unrelated XPath arrays.
  class KeyedCalendarExtractor
    Result = Struct.new(:records, :errors, keyword_init: true) do
      def valid?
        errors.empty?
      end
    end

    def self.call(html:, base_url:, item_xpath:, url_xpath:, key_xpath:, key_mode: :raw)
      new(html: html, base_url: base_url, item_xpath: item_xpath, url_xpath: url_xpath, key_xpath: key_xpath, key_mode: key_mode).call
    end

    def initialize(html:, base_url:, item_xpath:, url_xpath:, key_xpath:, key_mode:)
      @html, @base_url, @item_xpath, @url_xpath, @key_xpath = html, base_url, item_xpath, url_xpath, key_xpath
      @key_mode = key_mode.to_sym
      raise ArgumentError, "Unsupported key mode: #{@key_mode}" unless %i[raw url_last_segment].include?(@key_mode)
    end

    def call
      base = URI.parse(@base_url)
      raise ArgumentError, "base_url must be an absolute HTTP(S) URL" unless %w[http https].include?(base.scheme) && base.host && !base.userinfo

      document = Nokogiri::HTML(@html)
      cards = document.xpath(@item_xpath)
      errors = []
      errors << "no_event_cards" if cards.empty?
      records = cards.each_with_index.filter_map do |card, index|
        urls = card.xpath(@url_xpath)
        keys = card.xpath(@key_xpath)
        if urls.size != 1 || keys.size != 1
          errors << "ambiguous_card: #{index} url_count=#{urls.size} key_count=#{keys.size}"
          next
        end
        raw_url = urls.first.text.to_s.strip
        key = normalize_key(keys.first.text.to_s.strip)
        if key.empty? || raw_url.empty?
          errors << "blank_key_or_url: #{index}"
          next
        end
        begin
          uri = URI.join(@base_url, raw_url)
          unless %w[http https].include?(uri.scheme) && uri.host == base.host && uri.userinfo.nil?
            errors << "out_of_scope_url: #{index}"
            next
          end
          { key: key, url: uri.to_s }
        rescue URI::InvalidURIError
          errors << "invalid_url: #{index}"
          nil
        end
      end
      Result.new(records: records, errors: errors)
    rescue Nokogiri::XML::XPath::SyntaxError => e
      Result.new(records: [], errors: ["invalid_xpath: #{e.message}"])
    end

    private

    def normalize_key(value)
      return value if @key_mode == :raw
      URI.parse(value).path.to_s.split("/").reject(&:empty?).last.to_s
    rescue URI::InvalidURIError
      ""
    end
  end
end
