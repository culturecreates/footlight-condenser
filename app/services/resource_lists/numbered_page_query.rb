# frozen_string_literal: true

require "uri"

module ResourceLists
  # A URL-only contract for changing one numeric pagination parameter while
  # preserving the exact multiset of filters, including repeated query keys.
  # Does not prove the server applies those filters to returned event records.
  class NumberedPageQuery
    PARAMETERS = %w[page pag p pageNumber p_numb].freeze
    attr_reader :parameter, :first_page

    def initialize(start_url:, parameter: nil)
      @start = safe_uri(start_url)
      raise ArgumentError, "Expected HTTPS calendar URL" unless @start

      @pairs = URI.decode_www_form(@start.query.to_s)
      found = PARAMETERS.select { |key| @pairs.any? { |k, _| k == key } }
      @parameter = parameter || (found.one? && found.first)
      raise ArgumentError, "Set PAGE_PARAMETER to one numeric pagination key" unless PARAMETERS.include?(@parameter)

      values = @pairs.filter_map { |key, value| value if key == @parameter }
      raise ArgumentError, "Expected exactly one numeric #{@parameter} parameter" unless
        values.one? && values.first.match?(/\A\d+\z/)
      @first_page = values.first.to_i
      @filters = @pairs.reject { |key, _| key == @parameter }.tally
      # Keep every non-page query byte unchanged, including bare query keys,
      # percent-encoding style, duplicate filters, and empty parameters.
      @raw_parts = @start.query.to_s.split("&", -1).freeze
      @page_index = @raw_parts.index { |part| URI.decode_www_form(part).first&.first == @parameter }
      raise ArgumentError, "Cannot locate #{@parameter} in raw query" unless @page_index
    rescue URI::InvalidURIError, ArgumentError => e
      raise ArgumentError, "Invalid pagination URL: #{e.message}"
    end

    def url_for(page)
      raise ArgumentError, "Expected nonnegative page number" unless page.is_a?(Integer) && page >= 0
      parts = @raw_parts.dup
      raw_key = parts.fetch(@page_index).split("=", 2).first
      parts[@page_index] = "#{raw_key}=#{page}"
      target = @start.dup
      target.query = parts.join("&")
      target.to_s
    end

    def matches_page?(actual_url, page:)
      target = safe_uri(actual_url)
      return false unless target && same_origin_and_path?(target) && page.is_a?(Integer) && page >= 0

      pairs = URI.decode_www_form(target.query.to_s)
      pages = pairs.filter_map { |key, value| value if key == @parameter }
      pages == [page.to_s] && pairs.reject { |key, _| key == @parameter }.tally == @filters
    rescue ArgumentError
      false
    end

    private

    def safe_uri(value)
      uri = URI.parse(value.to_s)
      uri if uri.scheme == "https" && uri.host && !uri.userinfo && !uri.fragment
    end

    def same_origin_and_path?(other)
      @start.scheme == other.scheme && @start.host == other.host && @start.port == other.port &&
        @start.path.delete_suffix("/") == other.path.delete_suffix("/")
    end
  end
end
