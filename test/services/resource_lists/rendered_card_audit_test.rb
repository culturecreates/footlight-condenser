# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/rendered_card_audit"

class RenderedCardAuditTest < Minitest::Test
  def test_detects_missing_card_link_duplicate_between_pages_and_placeholder_tail
    pages = [
      { page: 1, url: "https://example.org/calendar?page=1",
        html: '<div class="event_pagination_content_wrapper"><article><a href="/event/a">A</a></article><article><a href="/event/shared">Shared</a></article></div>' },
      { page: 2, url: "https://example.org/calendar?page=2",
        html: '<div class="event_pagination_content_wrapper"><article><a href="/event/shared">Shared</a></article><article>Linkless card</article></div>' },
      { page: 3, url: "https://example.org/calendar?page=3",
        html: '<div class="event_pagination_content_wrapper"><div class="empty">No events</div></div>' }
    ]

    result = ResourceLists::RenderedCardAudit.analyze(pages: pages)
    assert_equal [2, 2, 1], result[:pages].map { |page| page[:direct_elements] }
    assert_equal 3, result[:total_direct_elements] - result[:cards_without_links].size
    assert_equal 2, result[:total_unique_absolute_hrefs]
    assert_equal 1, result[:repeated_absolute_hrefs_across_pages].size
    assert_equal [2, 3], result[:cards_without_links].map { |card| card[:page] }
    assert_equal true, result[:pages].last[:possible_empty_placeholder]
    assert_equal false, result[:verified_completeness]
  end

  def test_normalizes_fragments_without_collapsing_query_params
    pages = [{ page: 1, url: "https://example.org/list?page=1",
      html: '<div class="event_pagination_content_wrapper"><a href="/event/a?date=1#top">One</a><a href="/event/a?date=2">Two</a></div>' }]
    result = ResourceLists::RenderedCardAudit.analyze(pages: pages)
    assert_equal 2, result[:total_unique_absolute_hrefs]
    assert_equal [], result[:cards_without_links]
  end

  def test_missing_event_container_is_not_an_empty_event_page
    result = ResourceLists::RenderedCardAudit.analyze(pages: [
      { page: 1, url: "https://example.org/list?page=1", html: "<div>Blocked</div>" }
    ])
    assert_equal false, result[:pages].first[:container_found]
    assert_equal false, result[:pages].first[:possible_empty_placeholder]
    assert_equal false, result[:verified_completeness]
  end
end
