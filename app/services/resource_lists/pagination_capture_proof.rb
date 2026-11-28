# frozen_string_literal: true

require "digest"
require "json"
require "time"
require "uri"

module ResourceLists
  # Read-only proof that a supplied sequence of fetched calendar captures forms
  # one bounded, contiguous next-link chain. The caller must derive next_url and
  # terminal evidence from each successfully fetched page; this class does not
  # fetch HTML or prove that a site's HTML/JS exposes every event.
  class PaginationCaptureProof
    Result = Struct.new(:status, :errors, :urls, :record_count, :digest, keyword_init: true) do
      def complete? = status == "complete"
    end

    def self.call(start_url:, captures:, max_pages: 50, max_skew_seconds: 600)
      new(start_url:, captures:, max_pages:, max_skew_seconds:).call
    end

    def initialize(start_url:, captures:, max_pages:, max_skew_seconds:)
      @start_url, @captures, @max_pages, @max_skew_seconds = start_url, captures, max_pages, max_skew_seconds
    end

    def call
      errors = []
      return failure("invalid_bounds") unless @max_pages.is_a?(Integer) && @max_pages.positive? &&
        @max_skew_seconds.is_a?(Numeric) && @max_skew_seconds >= 0
      return failure("missing_captures") unless @captures.is_a?(Array) && @captures.any?
      return failure("page_limit_exceeded") if @captures.size > @max_pages

      start = canonical_url(@start_url)
      return failure("invalid_start_url") unless start
      urls, timestamps, record_count = [], [], 0
      expected = start
      @captures.each_with_index do |raw, index|
        unless raw.is_a?(Hash)
          errors << "invalid_capture:#{index}"
          break
        end
        page_url = canonical_url(raw[:url])
        if !page_url || origin(page_url) != origin(start)
          errors << "invalid_or_cross_origin_page:#{index}"
          break
        end
        if expected.nil? || page_url != expected
          errors << "broken_next_link_chain:#{index}"
          break
        end
        if urls.include?(page_url)
          errors << "pagination_cycle:#{index}"
          break
        end
        urls << page_url
        unless raw[:status] == "fetched" && raw[:records].is_a?(Array)
          errors << "unverified_fetch_or_extraction:#{index}"
          break
        end
        record_count += raw[:records].size
        time = parse_time(raw[:fetched_at])
        if time.nil?
          errors << "missing_or_invalid_capture_time:#{index}"
          break
        end
        timestamps << time
        next_url = raw[:next_url].nil? ? nil : canonical_url(raw[:next_url])
        if raw[:next_url] && (!next_url || origin(next_url) != origin(start))
          errors << "invalid_or_cross_origin_next:#{index}"
          break
        end
        if next_url
          if raw[:terminal_evidence]
            errors << "terminal_with_next_link:#{index}"
            break
          end
          if index == @captures.length - 1
            errors << "truncated_pagination:#{index}"
            break
          end
          expected = next_url
        else
          unless raw[:terminal_evidence] == "verified_no_next_link"
            errors << "missing_terminal_evidence:#{index}"
            break
          end
          if index != @captures.length - 1
            errors << "early_terminal:#{index}"
            break
          end
          expected = nil
        end
      end
      errors << "capture_freshness_skew" if timestamps.any? && timestamps.max - timestamps.min > @max_skew_seconds
      status = if errors.any?
        "incomplete"
      elsif record_count.zero?
        "no_event_discovery"
      else
        "complete"
      end
      digest = Digest::SHA256.hexdigest(JSON.generate(@captures.map do |raw|
        raw.is_a?(Hash) ? [raw[:url], raw[:next_url], raw[:status], raw[:records], raw[:fetched_at], raw[:terminal_evidence]] : raw
      end))
      Result.new(status:, errors:, urls:, record_count:, digest:)
    end

    private

    def failure(reason)
      Result.new(status: "incomplete", errors: [reason], urls: [], record_count: 0, digest: nil)
    end

    def canonical_url(value)
      uri = URI.parse(value.to_s)
      return unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo && !uri.fragment
      uri.normalize.to_s
    rescue URI::InvalidURIError
      nil
    end

    def origin(url)
      uri = URI.parse(url)
      [uri.scheme, uri.host, uri.port]
    end

    def parse_time(value)
      case value
      when Time then value
      when String then Time.iso8601(value)
      end
    rescue ArgumentError
      nil
    end
  end
end
