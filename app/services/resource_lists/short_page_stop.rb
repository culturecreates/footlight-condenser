# frozen_string_literal: true

module ResourceLists
  # A conservative, non-authoritative stop heuristic for numbered calendar
  # pages. Counts must be successfully extracted event URLs (one per card),
  # not all anchors, and must come from adjacent successfully fetched pages.
  # Always include the CURRENT page before applying this stop rule.
  class ShortPageStop
    def self.stop?(previous_count:, current_count:)
      unless [previous_count, current_count].all? { |count| count.is_a?(Integer) && count >= 0 }
        raise ArgumentError, "expected nonnegative integer event-link counts"
      end

      previous_count.positive? && current_count * 10 < previous_count * 9
    end
  end
end
