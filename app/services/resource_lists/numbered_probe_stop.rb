# frozen_string_literal: true

module ResourceLists
  # Stop *only* for hard failures or independently configured experimental
  # heuristics. A short HTML-link page is a hint, never terminal proof.
  # If the page links to the next numbered URL, a short-page heuristic must
  # not suppress that page, even when the heuristic is explicitly enabled.
  class NumberedProbeStop
    def self.reason(ajax_shell:, challenge:, repeated_content:, repeated_links:,
      short_page:, next_link_observed:, allow_heuristic_stop: false)
      return "ajax_shell_requires_rendering" if ajax_shell
      return "challenge_page_detected" if challenge
      return "repeated_content" if repeated_content
      return "repeated_link_inventory" if repeated_links
      return "heuristic_short_page" if allow_heuristic_stop && short_page && !next_link_observed

      nil
    end
  end
end
