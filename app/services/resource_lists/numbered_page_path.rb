# frozen_string_literal: true

require "uri"

module ResourceLists
  # Change only the numeric Page-N segment at the end of an HTTPS URL path.
  # Read-only navigation evidence; not a claim that the site exposes all records.
  class NumberedPagePath
    PARAMETER = "path:Page-"
    attr_reader :first_page

    def self.supports?(start_url)
      uri = URI.parse(start_url.to_s)
      uri.path.match?(%r{/Page-\d+/?\z}i)
    rescue URI::InvalidURIError
      false
    end

    def initialize(start_url:)
      @start = URI.parse(start_url.to_s)
      raise ArgumentError, "Expected HTTPS page URL without credentials or fragment" unless
        @start.scheme == "https" && @start.host && !@start.userinfo && !@start.fragment
      match = @start.path.match(%r{\A(.*?/)(Page-)(\d+)(/?)\z}i)
      raise ArgumentError, "Expected trailing Page-N path segment" unless match
      @prefix = match[1] + match[2]
      @trailing_slash = match[4]
      @first_page = match[3].to_i
      @width = match[3].start_with?("0") ? match[3].length : 0
      @filters = URI.decode_www_form(@start.query.to_s).tally
    rescue URI::InvalidURIError, ArgumentError => e
      raise ArgumentError, "Invalid path pagination URL: #{e.message}"
    end

    def parameter = PARAMETER

    def url_for(page)
      raise ArgumentError, "Expected nonnegative page number" unless page.is_a?(Integer) && page >= 0
      target = @start.dup
      digits = @width.positive? ? page.to_s.rjust(@width, "0") : page.to_s
      target.path = "#{@prefix}#{digits}#{@trailing_slash}"
      target.to_s
    end

    def matches_page?(actual_url, page:)
      uri = URI.parse(actual_url.to_s)
      return false unless page.is_a?(Integer) && page >= 0 && uri.scheme == @start.scheme &&
        uri.host == @start.host && uri.port == @start.port && !uri.userinfo && !uri.fragment
      uri.path == URI.parse(url_for(page)).path && URI.decode_www_form(uri.query.to_s).tally == @filters
    rescue URI::InvalidURIError, ArgumentError
      false
    end
  end
end
