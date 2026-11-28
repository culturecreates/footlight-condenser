# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/offset_json_terminal_evidence"

class OffsetJsonTerminalEvidenceTest < Minitest::Test
  def evaluate(**overrides)
    args = { offset: 0, page_size: 30, http_status: 200, content_type: "application/json", json_valid: true,
      schema_verified: true, record_count: 30 }
    ResourceLists::OffsetJsonTerminalEvidence.call(**args.merge(overrides))
  end

  def test_full_batch_without_metadata_is_only_forward_candidate
    result = evaluate
    assert_equal "forward_candidate_full_batch", result.status
    assert_equal 30, result.next_offset
    refute result.respond_to?(:complete?)
  end

  def test_explicit_has_more_proves_forward_only
    result = evaluate(has_more: true)
    assert_equal "forward_observed", result.status
    assert_equal 30, result.next_offset
  end

  def test_explicit_no_more_is_terminal_candidate_not_complete
    result = evaluate(offset: 60, record_count: 2, has_more: false)
    assert_equal "terminal_candidate_explicit", result.status
    assert_nil result.next_offset
  end

  def test_reported_total_is_provisional_terminal
    result = evaluate(offset: 60, record_count: 10, reported_total: 70)
    assert_equal "terminal_candidate_reported_total", result.status
    assert_nil result.next_offset
  end

  def test_short_batch_without_metadata_is_inconclusive
    assert_equal "inconclusive_short_or_empty_batch", evaluate(record_count: 10).status
    assert_equal "inconclusive_short_or_empty_batch", evaluate(record_count: 0).status
  end

  def test_empty_batch_with_more_flag_is_contradictory
    result = evaluate(record_count: 0, has_more: true)
    assert_equal "inconclusive", result.status
    assert_includes result.errors, "contradictory_forward_metadata"
  end

  def test_conflicting_total_and_has_more_is_inconclusive
    assert_includes evaluate(record_count: 10, reported_total: 100, has_more: false).errors,
      "contradictory_terminal_metadata"
    assert_includes evaluate(record_count: 30, reported_total: 30, has_more: true).errors,
      "contradictory_forward_metadata"
  end

  def test_http429_and_challenge_html_are_inconclusive
    assert_includes evaluate(http_status: 429).errors, "http_not_successful"
    assert_includes evaluate(content_type: "text/html", json_valid: false).errors, "not_json"
  end

  def test_no_schema_evidence_cannot_claim_terminal
    result = evaluate(schema_verified: false, has_more: false)
    assert_equal "inconclusive", result.status
    assert_includes result.errors, "unknown_response_schema"
  end

  def test_invalid_count_or_bad_flags_fail_closed
    assert_includes evaluate(record_count: 50).errors, "invalid_record_count"
    assert_includes evaluate(has_more: "false").errors, "invalid_has_more"
    assert_includes evaluate(reported_total: "100").errors, "invalid_reported_total"
  end
end
