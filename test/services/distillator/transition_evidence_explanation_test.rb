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
    assert_equal "Fix the fetch/cache failure first, then rerun the transition batch check.", explanation.next_action
  end

  test "fetch explanation uses explicit captcha wording" do
    website = websites(:one)
    evidence = Distillator::TransitionEvidence.new(
      website: website,
      url: "https://example.org/event",
      check_kind: "fetch_parity",
      status: "failed",
      checked_at: Time.current,
      details: {
        reason: "captcha_detected",
        failed_layer: "fetch",
        affected_url_count: 1,
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

    assert_equal "Captcha was detected while fetching one or more sampled URLs.", explanation.headline
    assert_equal "Resolve the captcha or use the direct inspection links for the affected URLs, then rerun the transition batch check.", explanation.next_action
  end

  test "export explanation does not claim pass when runtime budget is exhausted" do
    website = websites(:one)
    evidence = Distillator::TransitionEvidence.new(
      website: website,
      url: "https://example.org/event",
      check_kind: "export_diff",
      status: "pending",
      checked_at: Time.current,
      details: {
        reason: "transition_check_timeout_budget_exceeded"
      }
    )

    explanation = Distillator::TransitionEvidenceExplanation.call(
      check_kind: "export_diff",
      evidence: evidence,
      website: website,
      state: :inconclusive
    )

    assert_equal "Transition check reached its runtime budget before export coverage completed.", explanation.headline
    assert_equal "Rerun the transition batch check with enough runtime budget to finish export coverage.", explanation.next_action
  end

  test "statement explanation distinguishes optional warnings from blocking failures" do
    website = websites(:one)
    evidence = Distillator::TransitionEvidence.new(
      website: website,
      url: "https://example.org/event",
      check_kind: "statement_delta",
      status: "warning",
      checked_at: Time.current,
      details: {
        reason: "optional_statement_refresh_warning",
        critical_statements_failed_count: 0,
        optional_statements_failed_count: 2,
        optional_failing_statements: [
          { id: 201, source: "Description / en", webpage_url: "https://example.org/event", severity: "warning" }
        ],
        refresh_errors: ["Property id 5: {:cache=>[\"abort_update\"]}"]
      }
    )

    explanation = Distillator::TransitionEvidenceExplanation.call(
      check_kind: "statement_delta",
      evidence: evidence,
      website: website,
      state: :warning
    )

    assert_equal "warning", explanation.severity
    assert_equal "Critical statements passed; optional statement refresh warnings need review.", explanation.headline
    assert_includes explanation.details, "Optional statement warnings: 2"
    assert_equal "Review the optional statement refresh warnings before activating.", explanation.next_action
  end
end
