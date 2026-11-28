# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/numbered_page_url"

class NumberedPagePathTest < Minitest::Test
  START = "https://www.newegg.ca/USB-Cables/SubCategory/ID-2840/Page-3"

  def test_newegg_path_grammar
    page = ResourceLists::NumberedPageURL.build(start_url: START)
    assert_equal "path:Page-", page.parameter
    assert_equal 3, page.first_page
    assert_equal START, page.url_for(3)
    assert_equal START.sub("Page-3", "Page-20"), page.url_for(20)
    assert page.matches_page?(page.url_for(20), page: 20)
  end

  def test_filters_and_trailing_slash_are_preserved
    start = START + "/?lang=en&cat%5B%5D=A&cat%5B%5D=B"
    page = ResourceLists::NumberedPageURL.build(start_url: start)
    assert_equal start.sub("Page-3", "Page-4"), page.url_for(4)
    assert page.matches_page?(page.url_for(4), page: 4)
    refute page.matches_page?(page.url_for(4).sub("lang=en", "lang=fr"), page: 4)
    refute page.matches_page?(page.url_for(4).sub("cat%5B%5D=B", "cat%5B%5D=C"), page: 4)
  end

  def test_cross_origin_unrelated_paths_redirects_and_fragments_rejected
    page = ResourceLists::NumberedPageURL.build(start_url: START)
    refute page.matches_page?("https://other.example/USB-Cables/SubCategory/ID-2840/Page-4", page: 4)
    refute page.matches_page?("https://www.newegg.ca/Other/SubCategory/ID-2840/Page-4", page: 4)
    refute page.matches_page?(page.url_for(5), page: 4)
    refute page.matches_page?(page.url_for(4) + "#next", page: 4)
    refute page.matches_page?("https://www.newegg.ca/p/pl?N=100166495&page=4", page: 4)
  end

  def test_query_and_path_page_ambiguity_is_inconclusive
    assert_raises(ArgumentError) do
      ResourceLists::NumberedPageURL.build(start_url: START + "?page=3")
    end
  end

  def test_query_numbered_pagination_unchanged
    page = ResourceLists::NumberedPageURL.build(start_url: "https://example.org/events/?page=3&category=one")
    assert_kind_of ResourceLists::NumberedPageQuery, page
    assert_equal "https://example.org/events/?page=4&category=one", page.url_for(4)
  end

  def test_unsupported_and_unsafe_url_fails_closed
    assert_raises(ArgumentError) { ResourceLists::NumberedPageURL.build(start_url: START.sub("Page-3", "Page-three")) }
    assert_raises(ArgumentError) { ResourceLists::NumberedPageURL.build(start_url: START.sub("https://", "http://")) }
    assert_raises(ArgumentError) { ResourceLists::NumberedPageURL.build(start_url: START + "#fragment") }
  end

  def test_preserves_zero_padding_when_present
    page = ResourceLists::NumberedPageURL.build(start_url: START.sub("Page-3", "Page-003"))
    assert_equal START.sub("Page-3", "Page-004"), page.url_for(4)
  end
end
