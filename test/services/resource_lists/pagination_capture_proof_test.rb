# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/pagination_capture_proof"

class PaginationCaptureProofTest < Minitest::Test
  def capture(path, next_path: nil, records: ["event"], terminal: nil, time: "2026-11-27T14:00:00Z")
    { url: "https://example.org#{path}", next_url: next_path && "https://example.org#{next_path}",
      status: "fetched", records: records, terminal_evidence: terminal, fetched_at: time }
  end

  def check(pages, **opts)
    ResourceLists::PaginationCaptureProof.call(start_url: "https://example.org/events", captures: pages, **opts)
  end

  def test_valid_complete_chain_with_empty_tail
    result = check([capture("/events", next_path: "/events?page=2"),
      capture("/events?page=2", next_path: "/events?page=3"),
      capture("/events?page=3", records: [], terminal: "verified_no_next_link")])
    assert result.complete?
    assert_equal 2, result.record_count
    assert_equal 3, result.urls.size
    refute_nil result.digest
  end

  def test_all_empty_pages_are_not_sufficient_discovery_evidence
    result = check([capture("/events", records: [], terminal: "verified_no_next_link")])
    assert_equal "no_event_discovery", result.status
    refute result.complete?
  end

  def test_rejects_missing_middle_page
    result = check([capture("/events", next_path: "/events?page=2"),
      capture("/events?page=3", terminal: "verified_no_next_link")])
    assert_includes result.errors.first, "broken_next_link_chain"
  end

  def test_rejects_truncated_pagination
    result = check([capture("/events", next_path: "/events?page=2")])
    assert_includes result.errors.first, "truncated_pagination"
  end

  def test_rejects_empty_page_without_terminal_evidence
    result = check([capture("/events", records: [])])
    assert_includes result.errors.first, "missing_terminal_evidence"
  end

  def test_rejects_cross_origin_next_link
    result = check([capture("/events", next_path: "/events?page=2").merge(next_url: "https://evil.example/page/2")])
    assert_includes result.errors.first, "invalid_or_cross_origin_next"
  end

  def test_rejects_cycle
    result = check([capture("/events", next_path: "/events?page=2"),
      capture("/events?page=2", next_path: "/events"),
      capture("/events", terminal: "verified_no_next_link")])
    assert_includes result.errors.first, "pagination_cycle"
  end

  def test_rejects_failed_fetch
    result = check([capture("/events", terminal: "verified_no_next_link").merge(status: "failed")])
    assert_includes result.errors.first, "unverified_fetch_or_extraction"
  end

  def test_rejects_temporal_skew
    result = check([capture("/events", next_path: "/events?page=2"),
      capture("/events?page=2", terminal: "verified_no_next_link", time: "2026-11-27T15:00:00Z")])
    assert_includes result.errors, "capture_freshness_skew"
  end

  def test_rejects_page_limit
    result = check([capture("/events", next_path: "/events?page=2"),
      capture("/events?page=2", terminal: "verified_no_next_link")], max_pages: 1)
    assert_equal ["page_limit_exceeded"], result.errors
  end

  def test_rejects_extra_page_after_terminal
    result = check([capture("/events", terminal: "verified_no_next_link"),
      capture("/events?page=2", terminal: "verified_no_next_link")])
    assert_includes result.errors.first, "early_terminal"
  end
end
