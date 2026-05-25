require "test_helper"

class Distillator::TransitionEvidenceExplanationTest < ActiveSupport::TestCase
  test "fetch explanation distinguishes comparison failure from fetch failure" do
    website = websites(:one)
    evidence = Distillator::TransitionEvidence.new(
      website: website,
      url: "https://example.org/event",
      check_kind: "fetch_parity",
      status: "failed",
      checked_at: Time.current,
      details: {
        reason: "cache_compare_blocking_regression",
        failed_layer: "cache_compare",
        affected_url_count: 1,
        attempted_condenser_fetch: true,
        condenser_fetch_success: true,
        comparison_performed: true,
        legacy_lookup_status: "ok"
      }
    )

    explanation = Distillator::TransitionEvidenceExplanation.call(
      check_kind: "fetch_parity",
      evidence: evidence,
      website: website,
      state: :failed
    )

    assert_equal "Condenser and Wringer have a blocking parity mismatch.", explanation.headline
    assert_includes explanation.details, "Failed layer: Cache compare"
    assert_includes explanation.details, "Affected sampled URLs: 1"
    assert_includes explanation.details, "Condenser fetch: passed"
    assert_equal "Review the Condenser vs Wringer comparison for the affected URLs.", explanation.next_action
  end

  test "fetch explanation keeps fetch failure wording for real fetch failures" do
    website = websites(:one)
    evidence = Distillator::TransitionEvidence.new(
      website: website,
      url: "https://example.org/event",
      check_kind: "fetch_parity",
      status: "failed",
      checked_at: Time.current,
      details: {
        reason: "cache_health_failed",
        failed_layer: "fetch",
        affected_url_count: 2,
        attempted_condenser_fetch: true,
        condenser_fetch_success: false
      }
    )

    explanation = Distillator::TransitionEvidenceExplanation.call(
      check_kind: "fetch_parity",
      evidence: evidence,
      website: website,
      state: :failed
    )

    assert_equal "Condenser fetch/cache failed for one or more sampled URLs.", explanation.headline
    assert_equal "Fix the fetch/cache failure first, then rerun the transition check.", explanation.next_action
  end
end
