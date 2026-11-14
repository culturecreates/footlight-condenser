require "test_helper"

class Distillator::TransitionFetchSummaryTest < ActiveSupport::TestCase
  test "nine attempts and eight successful native fetches identify the actual failed URL" do
    rows = successful_rows
    rows[2].merge!(fetch_status: "failed", fetch_reason: "network_failure", http_response_code: 503,
      condenser_error: "Service unavailable")
    result = summarize(rows)
    assert_equal 9, result.attempted
    assert_equal 8, result.condenser_succeeded
    assert_equal 9, result.wringer_available
    assert_equal 8, result.paired
    assert_equal 8, result.compared
    assert_equal ["https://example.org/event/2"], result.issues.map { |issue| issue[:url] }
    assert_equal "Condenser", result.issues.first[:backend]
    assert_equal 503, result.issues.first[:http_code]
    assert_equal "Service unavailable", result.issues.first[:reason]
  end

  test "a Wringer failure is distinct from nine successful Condenser fetches" do
    rows = successful_rows
    rows[4].merge!(legacy_lookup_status: "unreachable", legacy_lookup_error: "Fresh Wringer request timed out",
      compare_missing: { "legacy" => true }, legacy_fetch: { upstream_http_code: 503 })
    result = summarize(rows)
    assert_equal 9, result.condenser_succeeded
    assert_equal 8, result.wringer_available
    assert_equal 8, result.paired
    assert_equal "Wringer", result.issues.first[:backend]
    assert_equal "https://example.org/event/4", result.issues.first[:url]
    assert_includes result.issues.first[:reason], "timed out"
  end

  test "a missing snapshot is not counted as available even if a stale status says ok" do
    rows = successful_rows
    rows[0][:compare_missing] = { "legacy" => true }
    result = summarize(rows)
    assert_equal 8, result.wringer_available
    assert_equal 8, result.paired
  end

  test "deadline before an attempt is a check runtime problem rather than a backend failure" do
    rows = successful_rows
    rows[8].merge!(attempted_condenser_fetch: false, fetch_status: "failed",
      fetch_reason: "transition_check_timeout_budget_exceeded", legacy_lookup_status: nil)
    result = summarize(rows)
    assert_equal "Transition check", result.issues.first[:backend]
    assert_includes result.issues.first[:reason], "before this URL was fetched"
    assert_nil result.wringer_available
  end

  test "older evidence without per-URL results does not invent successful retrievals" do
    result = Distillator::TransitionFetchSummary.call(fetch_details: { representative_webpage_count: 9, fetch_attempted_webpage_count: 9 }, statement_details: {})
    assert_equal 9, result.attempted
    assert_nil result.condenser_succeeded
    assert_nil result.wringer_available
    assert_nil result.paired
    assert_empty result.issues
  end

  test "removed source URLs give a validity check rather than a blind retry" do
    rows = successful_rows
    rows[0].merge!(fetch_status: "failed", fetch_reason: "http_404", http_response_code: 404)
    assert_includes summarize(rows).issues.first[:action], "still valid"
  end

  private

  def successful_rows
    9.times.map { |id| { url: "https://example.org/event/#{id}", fetch_status: "passed", attempted_condenser_fetch: true,
      legacy_lookup_status: "ok", compare_missing: { legacy: false, condenser: false } } }
  end

  def summarize(rows)
    Distillator::TransitionFetchSummary.call(fetch_details: { representative_webpage_count: 9, fetch_basis: "fresh_both",
      fetch_attempted_webpage_count: 9, representative_url_results: rows }, statement_details: { compared_webpage_count: 8 })
  end
end
