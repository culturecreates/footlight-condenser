require "test_helper"

class Distillator::TransitionStatusTest < ActiveSupport::TestCase
  test "no cache or evidence returns not checked" do
    website = build_website("Outside Feed", "outside-feed")

    status = Distillator::TransitionStatus.call(website: website, cache: nil)

    assert_equal :not_checked, status.status
    assert_equal :missing, status.fetch
    assert_equal :missing, status.statements
    assert_equal :missing, status.export
  end

  test "failed transport returns blocked and fetch failed" do
    website = build_website("Outside Feed", "outside-feed")
    cache = build_cache(signals: { "transport_success" => false, "content_success" => true }, health_status: "attempt_failed")

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :blocked, status.status
    assert_equal :failed, status.fetch
    assert_equal "Fix fetch/cache first, then rerun the transition check.", status.activation_recommendation[:next_action]
  end

  test "failed content returns blocked and fetch failed" do
    website = build_website("Outside Feed", "outside-feed")
    cache = build_cache(signals: { "transport_success" => true, "content_success" => false }, health_status: "attempt_failed")

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :blocked, status.status
    assert_equal :failed, status.fetch
  end

  test "la vitrine missing statement evidence returns blocked" do
    website = build_website("Tout Culture", "outside-seed")
    cache = build_cache(signals: { "transport_success" => true, "content_success" => true, "export_diff_checked" => true })

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :blocked, status.status
    assert_equal :missing, status.statements
  end

  test "la vitrine missing export evidence returns blocked" do
    website = build_website("Tout Culture", "outside-seed")
    cache = build_cache(signals: { "transport_success" => true, "content_success" => true, "statement_count_delta_acceptable" => true })

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :blocked, status.status
    assert_equal :missing, status.export
  end

  test "la vitrine cache signals alone do not satisfy statements and export checks" do
    website = build_website("Tout Culture", "outside-seed")
    cache = build_cache(
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "statement_count_delta_acceptable" => true,
        "export_diff_checked" => true
      }
    )

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :blocked, status.status
    assert_equal :missing, status.statements
    assert_equal :missing, status.export
  end

  test "ordinary missing export evidence returns review" do
    website = build_website("Outside Feed", "outside-feed")
    cache = build_cache(signals: { "transport_success" => true, "content_success" => true, "statement_count_delta_acceptable" => true })

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :review, status.status
    assert_equal :missing, status.export
  end

  test "ordinary sites still fall back to cache signals for statements and export" do
    website = build_website("Outside Feed", "outside-feed")
    cache = build_cache(
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "statement_count_delta_acceptable" => true,
        "export_diff_checked" => true
      }
    )

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :ready, status.status
    assert_equal :passed, status.statements
    assert_equal :passed, status.export
  end

  test "all required fresh evidence returns ready" do
    website = build_website("Tout Culture", "outside-seed")
    cache = build_cache(signals: { "transport_success" => true, "content_success" => true })
    website.transition_evidences.create!(url: "https://example.org/event", check_kind: "statement_delta", status: "checked", statement_count_delta_acceptable: true, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: "https://example.org/event", check_kind: "export_diff", status: "checked", export_diff_checked: true, checked_at: 1.hour.ago)

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :ready, status.status
    assert_equal :passed, status.fetch
    assert_equal :passed, status.statements
    assert_equal :passed, status.export
    assert_equal "Ready", status.activation_recommendation[:label]
  end

  test "evidence statuses expose checked missing failed and stale states" do
    website = build_website("Tout Culture", "outside-seed")
    cache = build_cache(signals: { "transport_success" => true, "content_success" => true })
    website.transition_evidences.create!(url: "https://example.org/event", check_kind: "fetch_parity", status: "checked", checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: "https://example.org/event", check_kind: "statement_delta", status: "failed", statement_count_delta_acceptable: false, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: "https://example.org/event", check_kind: "export_diff", status: "checked", export_diff_checked: true, checked_at: 4.days.ago)

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :checked, status.evidence_statuses["fetch_parity"]
    assert_equal :failed, status.evidence_statuses["statement_delta"]
    assert_equal :stale, status.evidence_statuses["export_diff"]
    assert_includes status.blockers, "Cannot activate yet: statements check failed."
    assert_not_includes status.blockers, "Cannot activate yet: statements check is missing."
    assert_equal "Blocked", status.activation_recommendation[:label]
    assert_equal "Cannot activate yet: statements check failed.", status.activation_recommendation[:reason]
  end

  test "activation can be blocked while export still passes" do
    website = build_website("Tout Culture", "outside-seed")
    cache = build_cache(signals: { "transport_success" => true, "content_success" => true })
    website.transition_evidences.create!(url: "https://example.org/event", check_kind: "statement_delta", status: "failed", statement_count_delta_acceptable: false, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: "https://example.org/event", check_kind: "export_diff", status: "checked", export_diff_checked: true, checked_at: 1.hour.ago)

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :blocked, status.status
    assert_equal :failed, status.statements
    assert_equal :passed, status.export
    assert_equal "Blocked", status.activation_recommendation[:label]
    assert_equal "Export", status.checks.last[:label]
    assert_equal :passed, status.checks.last[:state]
  end

  test "failed fetch with zero statement work marks statements not evaluated" do
    website = build_website("Tout Culture", "outside-seed")
    cache = build_cache(signals: { "transport_success" => false, "content_success" => false }, health_status: "empty_body")
    website.transition_evidences.create!(
      url: "https://example.org/event",
      check_kind: "statement_delta",
      status: "pending",
      checked_at: 1.hour.ago,
      details: {
        reason: "fetch_failed_before_statement_refresh",
        statements_refreshed_count: 0,
        statements_failed_count: 0
      }
    )
    website.transition_evidences.create!(
      url: "https://example.org/event",
      check_kind: "export_diff",
      status: "checked",
      export_diff_checked: true,
      checked_at: 1.hour.ago
    )

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :failed, status.fetch
    assert_equal :not_evaluated, status.statements
    assert_equal :passed, status.export
    assert_equal "Cannot activate yet: fetch check failed.", status.activation_recommendation[:reason]
    assert_equal "Fix fetch/cache first, then rerun the transition check.", status.activation_recommendation[:next_action]
  end

  test "no selected statements marks statements inconclusive" do
    website = build_website("Outside Feed", "outside-feed")
    cache = build_cache(signals: { "transport_success" => true, "content_success" => true })
    website.transition_evidences.create!(
      url: "https://example.org/event",
      check_kind: "statement_delta",
      status: "pending",
      checked_at: 1.hour.ago,
      details: {
        reason: "no_selected_statements",
        statements_refreshed_count: 0,
        statements_failed_count: 0
      }
    )

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :inconclusive, status.statements
    assert_equal "Verify selected sources/statements for the sampled webpages.", status.activation_recommendation[:next_action]
  end

  test "legacy lookup missing config keeps condenser fetch passed but marks review" do
    website = build_website("Outside Feed", "outside-feed")
    cache = build_cache(
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "statement_count_delta_acceptable" => true,
        "export_diff_checked" => true
      }
    )
    website.transition_evidences.create!(
      url: "https://example.org/event",
      check_kind: "fetch_parity",
      status: "checked",
      checked_at: 1.hour.ago,
      details: {
        attempted_condenser_fetch: true,
        condenser_fetch_success: true,
        comparison_performed: false,
        legacy_lookup_status: "missing_config",
        legacy_lookup_error: "missing_config",
        reason: "legacy_lookup_missing_config"
      }
    )

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :review, status.status
    assert_equal :passed, status.fetch
    assert_includes status.warnings, "Needs review: legacy Wringer endpoint is not configured for this environment."
    assert_equal "Configure the Wringer endpoint for staging, then rerun the transition check.", status.activation_recommendation[:next_action]
  end

  test "legacy lookup unreachable keeps condenser fetch passed but marks review" do
    website = build_website("Outside Feed", "outside-feed")
    cache = build_cache(
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "statement_count_delta_acceptable" => true,
        "export_diff_checked" => true
      }
    )
    website.transition_evidences.create!(
      url: "https://example.org/event",
      check_kind: "fetch_parity",
      status: "checked",
      checked_at: 1.hour.ago,
      details: {
        attempted_condenser_fetch: true,
        condenser_fetch_success: true,
        comparison_performed: false,
        legacy_lookup_status: "unreachable",
        legacy_lookup_error: "connection refused",
        reason: "legacy_lookup_unreachable"
      }
    )

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :review, status.status
    assert_equal :passed, status.fetch
    assert_includes status.warnings, "Needs review: legacy Wringer lookup failed during the latest transition check."
    assert_equal "Fix the legacy Wringer endpoint, then rerun the transition check.", status.activation_recommendation[:next_action]
  end

  test "legacy lookup body omitted keeps condenser fetch passed but marks review" do
    website = build_website("Outside Feed", "outside-feed")
    cache = build_cache(
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "statement_count_delta_acceptable" => true,
        "export_diff_checked" => true
      }
    )
    website.transition_evidences.create!(
      url: "https://example.org/event",
      check_kind: "fetch_parity",
      status: "checked",
      checked_at: 1.hour.ago,
      details: {
        attempted_condenser_fetch: true,
        condenser_fetch_success: true,
        comparison_performed: false,
        legacy_lookup_status: "body_omitted",
        legacy_lookup_error: "legacy_body_omitted",
        reason: "legacy_lookup_body_omitted"
      }
    )

    status = Distillator::TransitionStatus.call(website: website, cache: cache)

    assert_equal :review, status.status
    assert_equal :passed, status.fetch
    assert_includes status.warnings, "Needs review: legacy Wringer body was omitted from the comparison endpoint."
    assert_not_includes status.blockers, "Cannot activate yet: fetch check failed."
    assert_equal "Verify the legacy Wringer body endpoint or compare using the legacy inspection link.", status.activation_recommendation[:next_action]
  end

  private

  def build_website(name, seedurl)
    Website.create!(
      name: name,
      seedurl: seedurl,
      graph_name: "https://example.org/#{seedurl}",
      default_language: "en",
      distillator_mode: "shadow"
    )
  end

  def build_cache(signals:, health_status: "healthy")
    Distillator::FetchCache.new(
      uri_key: CGI.escape("https://example.org/event"),
      normalized_url: "https://example.org/event",
      signals: signals,
      health_status: health_status,
      successful_refresh: 1.hour.ago,
      scrape_date: 1.hour.ago
    )
  end
end
