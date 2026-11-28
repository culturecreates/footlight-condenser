# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/numbered_pager_evidence"

class NumberedPagerEvidenceTest < Minitest::Test
  def row(page, count: 42, links: [1, 2, 3, 4, 5], active: [page])
    { page: page, records: count, pager_numbers: links, active_pages: active }
  end

  def check(rows)
    ResourceLists::NumberedPagerEvidence.call(captures: rows)
  end

  def test_hector_charland_captured_five_pages
    result = check((1..4).map { |page| row(page) } + [row(5, count: 23)])
    assert result.terminal_candidate?
    assert_equal 5, result.advertised_last
    assert result.listed_pages_captured
    assert result.terminal_page_observed
    assert_empty result.errors
  end

  def test_hector_charland_out_of_range_boundary
    result = check([row(5, count: 23), row(6, count: 0, active: []), row(7, count: 0, active: [])])
    assert result.terminal_candidate?
    refute result.listed_pages_captured
    assert_equal [6, 7], result.out_of_range_pages
  end

  def test_does_not_claim_an_authoritative_complete_discovery
    result = check([row(5, count: 23)])
    assert_equal "terminal_candidate", result.status
    refute result.listed_pages_captured
    refute result.respond_to?(:complete?)
  end

  def test_rejects_missing_active_current_page
    result = check([row(5, active: [])])
    refute result.terminal_candidate?
    assert_includes result.errors, "missing_or_conflicting_active_page:5"
  end

  def test_rejects_active_page_out_of_range
    result = check([row(5, count: 23), row(6, count: 0, active: [5])])
    assert_includes result.errors, "out_of_range_not_empty:6"
  end

  def test_rejects_events_beyond_advertised_end
    result = check([row(5, count: 23), row(6, count: 1, active: [])])
    refute result.terminal_candidate?
    assert_includes result.errors, "out_of_range_not_empty:6"
  end

  def test_rejects_pagination_window_or_gap
    result = check([row(5, links: [3, 4, 5])])
    assert_includes result.errors, "invalid_or_windowed_pager_range"
  end

  def test_rejects_changing_page_range_between_captures
    result = check([row(4), row(5, links: [1, 2, 3, 4, 5, 6])])
    assert_includes result.errors, "inconsistent_pager_range"
  end

  def test_rejects_duplicate_capture
    result = check([row(5), row(5)])
    assert_includes result.errors, "duplicate_page"
  end

  def test_requires_terminal_page_capture
    result = check([row(1), row(2)])
    refute result.terminal_candidate?
    refute result.terminal_page_observed
  end
end
