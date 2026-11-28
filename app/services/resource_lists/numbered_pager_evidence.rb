# frozen_string_literal: true

module ResourceLists
  # Read-only structural evidence from a numbered pager. Accepts observed DOM
  # facts; intentionally does NOT claim ResourceList discovery is complete.
  #
  # A pager can display a *window* of page numbers instead of the full set.
  # Only a site-specific contract plus validated captures can elevate this
  # observation to authoritative terminal evidence.
  class NumberedPagerEvidence
    Result = Struct.new(:status, :errors, :advertised_last, :listed_pages_captured,
      :terminal_page_observed, :out_of_range_pages, keyword_init: true) do
      def terminal_candidate? = status == "terminal_candidate"
    end

    def self.call(captures:)
      new(captures:).call
    end

    def initialize(captures:)
      @captures = captures
    end

    def call
      return invalid("missing_captures") unless @captures.is_a?(Array) && @captures.any?
      return invalid("invalid_capture") unless @captures.all? { |row| valid_row?(row) }

      numbers = @captures.map { |row| row[:page] }
      return invalid("duplicate_page") unless numbers.uniq == numbers
      return invalid("unordered_pages") unless numbers == numbers.sort

      ranges = @captures.map { |row| row[:pager_numbers].sort }
      return invalid("inconsistent_pager_range") unless ranges.uniq.length == 1
      advertised = ranges.first
      return invalid("invalid_or_windowed_pager_range") if advertised.empty? ||
        advertised != (1..advertised.last).to_a
      last = advertised.last

      errors = @captures.filter_map do |row|
        page = row[:page]
        if page <= last
          "missing_or_conflicting_active_page:#{page}" unless row[:active_pages] == [page]
        elsif !row[:active_pages].empty? || !row[:records].zero?
          "out_of_range_not_empty:#{page}"
        end
      end

      coverage = (1..last).all? { |page| numbers.include?(page) }
      terminal = @captures.any? { |row| row[:page] == last && row[:active_pages] == [last] }
      overflow = numbers.select { |page| page > last }
      Result.new(status: errors.empty? && terminal ? "terminal_candidate" : "inconclusive",
        errors:, advertised_last: last, listed_pages_captured: coverage,
        terminal_page_observed: terminal, out_of_range_pages: overflow)
    end

    private

    def valid_row?(row)
      row.is_a?(Hash) && row[:page].is_a?(Integer) && row[:page].positive? &&
        row[:records].is_a?(Integer) && row[:records] >= 0 &&
        row[:pager_numbers].is_a?(Array) && row[:pager_numbers].all? { |n| n.is_a?(Integer) && n.positive? } &&
        row[:active_pages].is_a?(Array) && row[:active_pages].all? { |n| n.is_a?(Integer) && n.positive? } &&
        row[:pager_numbers].uniq == row[:pager_numbers] && row[:active_pages].uniq == row[:active_pages]
    end

    def invalid(error)
      Result.new(status: "inconclusive", errors: [error], advertised_last: nil,
        listed_pages_captured: false, terminal_page_observed: false, out_of_range_pages: [])
    end
  end
end
