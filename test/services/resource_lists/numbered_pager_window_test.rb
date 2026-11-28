# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/numbered_pager_window"
require_relative "../../../app/services/resource_lists/numbered_page_query"

class NumberedPagerWindowTest < Minitest::Test
  BASE = 'https://lepointdevente.com/?q=&type=physical&locality=2234&radius=30&categories=%7B%221%22%3A0%7D&lang=fr&page=1'

  def setup
    @pagination = ResourceLists::NumberedPageQuery.new(start_url: BASE)
  end

  def url(page)
    @pagination.url_for(page)
  end

  def inspect(links, page:)
    ResourceLists::NumberedPagerWindow.call(links:, pagination: @pagination, page:)
  end

  def test_page_one_ignores_accessibility_fragments
    result = inspect(["#{url(1)}#skip-content-anchor", "#{url(1)}#", url(2)], page: 1)
    assert_equal [2], result.numbers
    assert_equal [url(2)], result.urls
    assert result.next_page_number_link_observed
  end

  def test_page_two_sliding_window
    result = inspect(["#{url(2)}#skip-content-anchor", url(3), url(4)], page: 2)
    assert_equal [3, 4], result.numbers
    assert result.next_page_number_link_observed
  end

  def test_page_three_sliding_window
    result = inspect(["#{url(3)}#skip-content-anchor", url(2), url(4)], page: 3)
    assert_equal [2, 4], result.numbers
    assert result.next_page_number_link_observed
  end

  def test_absence_of_a_next_number_is_not_terminal_proof
    result = inspect([url(3), url(2)], page: 3)
    assert_equal [2, 3], result.numbers
    refute result.next_page_number_link_observed
    refute result.respond_to?(:complete?)
  end

  def test_keeps_only_matching_origin_path_and_filters
    links = [url(2), url(2).sub("radius=30", "radius=31"),
      url(2).sub("%221%22", "%2211%22"),
      url(2).sub("locality=2234", "locality=2235"),
      url(2).sub("lang=fr", "lang=en"),
      url(2).sub("q=&", ""),
      url(2).sub("lepointdevente.com", "evil.example"),
      url(2).sub("/?", "/elsewhere?")]
    assert_equal [2], inspect(links, page: 1).numbers
  end

  def test_rejects_fragment_even_on_next_page
    result = inspect(["#{url(2)}#events", "#{url(2)}#"], page: 1)
    assert_empty result.urls
    refute result.next_page_number_link_observed
  end

  def test_deduplicates_valid_links_and_sorts_window
    result = inspect([url(4), url(2), url(4), url(3)], page: 2)
    assert_equal [2, 3, 4], result.numbers
  end

  def test_handles_malformed_href_as_diagnostic_noise
    result = inspect(["http://[oops", "https://lepointdevente.com/?page=bad", url(2)], page: 1)
    assert_equal [2], result.numbers
  end

  def test_zero_based_page_index_is_supported
    query = ResourceLists::NumberedPageQuery.new(start_url: "https://example.org/calendar?page=0&lang=fr")
    result = ResourceLists::NumberedPagerWindow.call(links: [query.url_for(1)], pagination: query, page: 0)
    assert_equal [1], result.numbers
    assert result.next_page_number_link_observed
  end

  def test_invalid_current_page_is_rejected
    assert_raises(ArgumentError) { inspect([], page: -1) }
  end
end
