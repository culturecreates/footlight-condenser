# frozen_string_literal: true

require "time"

module ResourceLists
  # Read-only consistency check for a numbered calendar which explicitly
  # advertises a total number of occurrences and a last page. Distinct event
  # URLs are deliberately NOT used for the total: a show can have several dates.
  #
  # The collector must supply truthful, successfully fetched per-page counts,
  # observed result totals and last-page indicators from real responses.
  # This proves arithmetic consistency, NOT authoritative discovery or safety
  # to delete/retire previously known ResourceList pages.
  class NumberedTotalEvidence
    Result = Struct.new(:status, :errors, :advertised_total, :advertised_last,
      :pages_captured, :occurrences_captured, keyword_init: true) do
      def terminal_candidate? = status == "terminal_candidate"
    end

    def self.call(captures:, page_size:, max_pages: 50, max_skew_seconds: 300)
      new(captures:, page_size:, max_pages:, max_skew_seconds:).call
    end

    def initialize(captures:, page_size:, max_pages:, max_skew_seconds:)
      @captures = captures
      @page_size = page_size
      @max_pages = max_pages
      @max_skew_seconds = max_skew_seconds
    end

    def call
      return inconclusive("invalid_configuration") unless positive_integer?(@page_size) &&
        positive_integer?(@max_pages) && positive_integer?(@max_skew_seconds)
      return inconclusive("missing_captures") unless @captures.is_a?(Array) && @captures.any?
      return inconclusive("invalid_capture") unless @captures.all? { |row| valid_row?(row) }

      pages = @captures.map { |row| row.fetch(:page) }
      return inconclusive("unordered_or_duplicate_pages") unless pages == pages.sort && pages.uniq == pages

      totals = @captures.map { |row| row.fetch(:advertised_total) }.uniq
      lasts = @captures.map { |row| row.fetch(:advertised_last) }.uniq
      errors = []
      errors << "inconsistent_total" unless totals.one?
      errors << "inconsistent_last_page" unless lasts.one?
      total = totals.one? ? totals.first : nil
      last = lasts.one? ? lasts.first : nil

      errors << "empty_requires_independent_evidence" if total == 0
      if total && total.positive? && last
        expected_last = (total + @page_size - 1) / @page_size
        errors << "total_disagrees_with_last_page" unless expected_last == last
      end
      errors << "page_limit_exceeded" if pages.size > @max_pages || (last && last > @max_pages)
      errors << "missing_or_extra_pages" if last && last <= @max_pages && pages != (1..last).to_a

      if total && total.positive? && last && last <= @max_pages
        @captures.each do |row|
          page = row.fetch(:page)
          next if page > last
          expected = page == last ? total - @page_size * (last - 1) : @page_size
          errors << "wrong_occurrence_count:#{page}" unless row.fetch(:records) == expected
        end
        errors << "total_does_not_match_occurrences" if @captures.sum { |row| row.fetch(:records) } != total
      end

      timestamps = @captures.map { |row| Time.iso8601(row.fetch(:fetched_at)) }
      errors << "capture_time_skew" if timestamps.max - timestamps.min > @max_skew_seconds

      Result.new(status: errors.empty? ? "terminal_candidate" : "inconclusive", errors:,
        advertised_total: total, advertised_last: last, pages_captured: pages,
        occurrences_captured: @captures.sum { |row| row.fetch(:records) })
    rescue ArgumentError
      inconclusive("invalid_timestamp")
    end

    private

    def positive_integer?(value) = value.is_a?(Integer) && value.positive?

    def valid_row?(row)
      row.is_a?(Hash) && positive_integer?(row[:page]) &&
        row[:records].is_a?(Integer) && row[:records] >= 0 &&
        row[:advertised_total].is_a?(Integer) && row[:advertised_total] >= 0 &&
        positive_integer?(row[:advertised_last]) &&
        row[:fetched_at].is_a?(String) && !row[:fetched_at].empty?
    end

    def inconclusive(error)
      Result.new(status: "inconclusive", errors: [error], advertised_total: nil,
        advertised_last: nil, pages_captured: [], occurrences_captured: 0)
    end
  end
end
