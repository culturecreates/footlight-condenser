# frozen_string_literal: true

require "uri"

module ResourceLists
  # Read-only inventory of numbered hrefs in a *possibly sliding* pager.
  # Fragment links and changed filters cannot count as page navigation.
  # A link to page+1 is not proof of an explicit "Next" control, nor terminal
  # evidence; a visible window's highest number is not the final page.
  class NumberedPagerWindow
    Result = Struct.new(:numbers, :urls, :next_page_number_link_observed, keyword_init: true)

    def self.call(links:, pagination:, page:)
      raise ArgumentError, "invalid page" unless page.is_a?(Integer) && page >= 0
      found = {}
      links.each do |link|
        uri = URI.parse(link.to_s)
        next if uri.fragment # Includes href="#" and #skip-content-anchor.
        pairs = URI.decode_www_form(uri.query.to_s)
        values = pairs.filter_map { |key, value| value if key == pagination.parameter }
        next unless values.one? && values.first.match?(/\A\d+\z/)
        number = values.first.to_i
        next unless pagination.matches_page?(uri.to_s, page: number)
        found[number] ||= uri.to_s
      rescue URI::InvalidURIError, ArgumentError
        next
      end
      numbers = found.keys.sort
      Result.new(numbers:, urls: numbers.map { |number| found.fetch(number) },
        next_page_number_link_observed: numbers.include?(page + 1))
    end
  end
end
