# frozen_string_literal: true

module ResourceLists
  # Advisory stop heuristic for consecutive successfully fetched calendar pages.
  # Compare ALL HTML anchor elements with href (not event URLs), so sites do
  # not need a custom event selector just to detect a short final page.
  #
  # Include the current page before stopping. This is NOT proof of complete
  # discovery; page caps, fetch checks and last-good retention still apply.
  class ShortPageStop
    def self.stop?(previous_count:, current_count:)
      unless [previous_count, current_count].all? { |count| count.is_a?(Integer) && count >= 0 }
        raise ArgumentError, "expected nonnegative integer link counts"
      end

      previous_count.positive? && current_count * 10 < previous_count * 9
    end
  end
end
