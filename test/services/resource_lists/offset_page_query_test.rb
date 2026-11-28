# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/offset_page_query"

class OffsetPageQueryTest < Minitest::Test
  START = "https://www.amazon.ca/d2b/api/v1/products/search?pageSize=30&startIndex=0&calculateRefinements=true&rankingContext=%7B%22pageTypeId%22%3A%22blackfriday%22%7D&filters=%7B%22excludedTags%22%3A%5B%22predefined-request%23deals-collection-deals-under-25%22%5D%7D"

  def test_offsets_advance_by_page_size_with_original_raw_filters
    q = ResourceLists::OffsetPageQuery.new(start_url: START)
    assert_equal 0, q.start_index
    assert_equal 30, q.page_size
    assert_equal 30, q.next_offset
    assert_equal START.sub("startIndex=0", "startIndex=30"), q.url_for(offset: 30)
    assert_equal START.sub("startIndex=0", "startIndex=60"), q.url_for(offset: 60)
  end

  def test_validated_next_url_same_query_identity
    q = ResourceLists::OffsetPageQuery.new(start_url: START)
    assert q.matches_offset?(q.url_for(offset: 30), offset: 30)
    refute q.matches_offset?(q.url_for(offset: 60), offset: 30)
    refute q.matches_offset?(q.url_for(offset: 30).sub("pageSize=30", "pageSize=20"), offset: 30)
  end

  def test_rejects_changed_encoded_filters
    q = ResourceLists::OffsetPageQuery.new(start_url: START)
    refute q.matches_offset?(q.url_for(offset: 30).sub("blackfriday", "normal"), offset: 30)
    refute q.matches_offset?(q.url_for(offset: 30).sub("deals-under-25", "deals-under-50"), offset: 30)
  end

  def test_rejects_other_destinations
    q = ResourceLists::OffsetPageQuery.new(start_url: START)
    refute q.matches_offset?(q.url_for(offset: 30).sub("amazon.ca", "example.com"), offset: 30)
    refute q.matches_offset?(q.url_for(offset: 30).sub("/products/search", "/other/search"), offset: 30)
    refute q.matches_offset?(q.url_for(offset: 30) + "#fragment", offset: 30)
  end

  def test_fails_closed_without_unambiguous_offset_and_size
    assert_raises(ArgumentError) { ResourceLists::OffsetPageQuery.new(start_url: START + "&startIndex=30") }
    assert_raises(ArgumentError) { ResourceLists::OffsetPageQuery.new(start_url: START.sub("pageSize=30", "pageSize=0")) }
    assert_raises(ArgumentError) { ResourceLists::OffsetPageQuery.new(start_url: START.sub("startIndex=0", "startIndex=-1")) }
    assert_raises(ArgumentError) { ResourceLists::OffsetPageQuery.new(start_url: START.sub("https://", "http://")) }
  end

  def test_bare_and_duplicate_filter_keys_preserved
    url = START + "&search_query&tag=A&tag=B"
    q = ResourceLists::OffsetPageQuery.new(start_url: url)
    assert_equal url.sub("startIndex=0", "startIndex=30"), q.url_for(offset: 30)
    assert q.matches_offset?(q.url_for(offset: 30), offset: 30)
    refute q.matches_offset?(q.url_for(offset: 30).sub("&tag=B", ""), offset: 30)
  end
end
