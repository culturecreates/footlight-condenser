# frozen_string_literal: true

require "uri"

module ResourceLists
  # URL-only offset pagination grammar. The caller is responsible for proving
  # that a fetched response is genuine JSON and that the next offset exists.
  # Unchanged encoded filters/ranking remain byte-for-byte identical.
  class OffsetPageQuery
    attr_reader :start_index, :page_size, :offset_key, :page_size_key

    def initialize(start_url:, offset_key: "startIndex", page_size_key: "pageSize")
      @start = URI.parse(start_url.to_s)
      raise ArgumentError, "Expected HTTPS URL without credentials or fragment" unless
        @start.scheme == "https" && @start.host && !@start.userinfo && !@start.fragment
      @offset_key, @page_size_key = offset_key, page_size_key
      raise ArgumentError, "Expected distinct query parameter names" unless
        [offset_key, page_size_key].all? { |key| key.is_a?(String) && key.match?(/\A[a-zA-Z][a-zA-Z0-9]*\z/) } &&
        offset_key != page_size_key
      @raw_parts = @start.query.to_s.split("&", -1).freeze
      @pairs = URI.decode_www_form(@start.query.to_s)
      @offset_index = key_index(offset_key)
      @page_size_index = key_index(page_size_key)
      @start_index = numeric_value(offset_key, zero_allowed: true)
      @page_size = numeric_value(page_size_key, zero_allowed: false)
      @filters = @pairs.reject { |key, _| key == @offset_key }.tally
    rescue URI::InvalidURIError, ArgumentError => e
      raise ArgumentError, "Invalid offset pagination URL: #{e.message}"
    end

    def url_for(offset:)
      raise ArgumentError, "Expected nonnegative offset" unless offset.is_a?(Integer) && offset >= 0
      parts = @raw_parts.dup
      raw_key = parts.fetch(@offset_index).split("=", 2).first
      parts[@offset_index] = "#{raw_key}=#{offset}"
      target = @start.dup
      target.query = parts.join("&")
      target.to_s
    end

    def next_offset(offset: @start_index)
      raise ArgumentError, "Expected nonnegative offset" unless offset.is_a?(Integer) && offset >= 0
      offset + @page_size
    end

    def matches_offset?(actual_url, offset:)
      uri = URI.parse(actual_url.to_s)
      return false unless offset.is_a?(Integer) && offset >= 0 &&
        uri.scheme == @start.scheme && uri.host == @start.host && uri.port == @start.port &&
        uri.path == @start.path && !uri.userinfo && !uri.fragment
      pairs = URI.decode_www_form(uri.query.to_s)
      offsets = pairs.filter_map { |key, value| value if key == @offset_key }
      offsets == [offset.to_s] && pairs.reject { |key, _| key == @offset_key }.tally == @filters
    rescue URI::InvalidURIError, ArgumentError
      false
    end

    private

    def key_index(key)
      positions = @raw_parts.each_index.select do |i|
        URI.decode_www_form(@raw_parts.fetch(i)).first&.first == key
      end
      raise ArgumentError, "Expected exactly one #{key} query parameter" unless positions.one?
      positions.first
    end

    def numeric_value(key, zero_allowed:)
      values = @pairs.filter_map { |name, value| value if name == key }
      raise ArgumentError, "Expected exactly one numeric #{key}" unless values.one? && values.first.match?(/\A\d+\z/)
      n = Integer(values.first, 10)
      raise ArgumentError, "Invalid #{key} value" unless zero_allowed ? n >= 0 : n.positive?
      n
    end
  end
end
