# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/numbered_total_evidence"

class NumberedTotalEvidenceTest < Minitest::Test
  def captures(total:, page_size: 24, last: (total + page_size - 1) / page_size,
    time: "2026-11-27T18:00:00Z")
    (1..last).map do |page|
      { page:, records: page == last ? total - page_size * (last - 1) : page_size,
        advertised_total: total, advertised_last: last, fetched_at: time }
    end
  end

  def check(rows, **opts)
    ResourceLists::NumberedTotalEvidence.call(captures: rows, page_size: 24, **opts)
  end

  def test_co_motion_nine_pages_for_211_occurrences
    result = check(captures(total: 211))
    assert result.terminal_candidate?
    assert_equal 211, result.occurrences_captured
    assert_equal 9, result.advertised_last
    assert_equal 19, captures(total: 211).last.fetch(:records)
    assert_empty result.errors
    refute result.respond_to?(:complete?)
  end

  def test_prior_snapshots_with_209_and_220_are_internally_valid_when_separate
    assert check(captures(total: 209)).terminal_candidate?
    assert check(captures(total: 220)).terminal_candidate?
    assert_equal 10, captures(total: 220).length
  end

  def test_rejects_mixed_snapshots_even_when_every_page_was_fetched
    rows = captures(total: 211)
    rows.last[:advertised_total] = 209
    assert_includes check(rows).errors, "inconsistent_total"
  end

  def test_rejects_different_advertised_last_page
    rows = captures(total: 211)
    rows.last[:advertised_last] = 10
    assert_includes check(rows).errors, "inconsistent_last_page"
  end

  def test_rejects_missing_middle_page
    rows = captures(total: 211).reject { |r| r[:page] == 5 }
    assert_includes check(rows).errors, "missing_or_extra_pages"
  end

  def test_rejects_missing_terminal_page
    rows = captures(total: 211).first(8)
    assert_includes check(rows).errors, "missing_or_extra_pages"
  end

  def test_rejects_duplicate_or_out_of_order_pages
    rows = captures(total: 211)
    assert_includes check(rows + [rows.last]).errors, "unordered_or_duplicate_pages"
    assert_includes check(rows.reverse).errors, "unordered_or_duplicate_pages"
  end

  def test_rejects_missing_occurrences_or_overfull_last_page
    rows = captures(total: 211)
    rows[3][:records] -= 1
    assert_includes check(rows).errors, "wrong_occurrence_count:4"
    rows = captures(total: 211)
    rows.last[:records] = 24
    assert_includes check(rows).errors, "wrong_occurrence_count:9"
  end

  def test_rejects_conflicting_total_and_page_count
    rows = captures(total: 211)
    rows.each { |row| row[:advertised_last] = 10 }
    assert_includes check(rows).errors, "total_disagrees_with_last_page"
  end

  def test_rejects_stale_or_separated_capture_times
    rows = captures(total: 211)
    rows.last[:fetched_at] = "2026-11-27T18:10:00Z"
    assert_includes check(rows).errors, "capture_time_skew"
  end

  def test_does_not_authorize_empty_calendar
    rows = [{ page: 1, records: 0, advertised_total: 0, advertised_last: 1,
      fetched_at: "2026-11-27T18:00:00Z" }]
    assert_includes check(rows).errors, "empty_requires_independent_evidence"
  end

  def test_rejects_invalid_or_excessive_inputs
    assert_includes check([]).errors, "missing_captures"
    assert_includes check(captures(total: 211), max_pages: 8).errors, "page_limit_exceeded"
    assert_includes check(captures(total: 211).tap { |r| r.first[:fetched_at] = "yesterday" }).errors, "invalid_timestamp"
    assert_includes check(captures(total: 211).tap { |r| r.first[:advertised_total] = "211" }).errors, "invalid_capture"
    result = ResourceLists::NumberedTotalEvidence.call(captures: captures(total: 211), page_size: 0)
    assert_includes result.errors, "invalid_configuration"
  end

  def test_untrusted_huge_page_count_fails_without_allocating_a_range
    rows = captures(total: 211)
    rows.each { |row| row[:advertised_last] = 1_000_000_000 }
    result = check(rows)
    assert_includes result.errors, "page_limit_exceeded"
    refute result.terminal_candidate?
  end
end
