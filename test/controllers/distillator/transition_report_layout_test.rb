require "test_helper"

class Distillator::TransitionReportLayoutTest < ActionDispatch::IntegrationTest
  setup do
    @website = Website.create!(name: "Transition pilot", seedurl: "petittheatre-org", default_language: "fr",
      graph_name: "https://example.org/transition-layout", distillator_mode: "shadow")
    @url = "https://example.org/event/one"
    @other_url = "https://example.org/event/two"
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::TransitionCheckRunner.expects(:call).never
    Distillator::RefreshRunner.expects(:call).never
    ExportArtsdataService.expects(:call).never
  end

  test "ready report has one decision three checks and closed supporting details" do
    run = completed_run
    assert_no_difference ["Statement.count", "Distillator::TransitionRun.count", "Distillator::RolloutEvent.count"] do
      get distillator_shadow_report_site_path(@website)
    end
    assert_response :success
    assert_select '.transition-decision--passed h2', text: "Ready to activate", count: 1
    assert_select '.transition-next-action', count: 1
    assert_select '.transition-check-results > li', count: 3
    assert_select '.transition-check-results .transition-result--passed', count: 3
    assert_select '[data-check="statement_delta"]', text: /Selected sources only, in Standard and Strict modes/
    assert_select '[data-check="export_diff"]', text: /stored data in this environment; separate from fresh extraction coverage/
    assert_select '.transition-completed-context', text: /Completed transition run:\s*##{run.id}/
    assert_select '#transition-checked-scope:not([open]), #transition-report-audit:not([open]), #transition-url-diagnostics:not([open]), #transition-recorded-fetches:not([open])', count: 4
    assert_select '.transition-report-heading', text: /Current mode:\s*Shadow.*Serving backend:\s*Wringer/m
    assert_select '.transition-primary-action', text: "Review activation"
    assert_equal "shadow", @website.reload.distillator_mode
  end

  test "missing Wringer snapshot is red retrieval amber coverage and green stored export with an immutable evidence link" do
    run = completed_run(missing_wringer: true)
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select '.transition-decision--review h2', text: "Incomplete evidence — stay in Shadow"
    assert_select '[data-check="fetch_parity"] .transition-result--failed', text: /Failed/
    assert_select '[data-check="statement_delta"] .transition-result--review', text: /Incomplete/
    assert_select '[data-check="export_diff"] .transition-result--passed', text: /Passed/
    assert_select '[data-check="statement_delta"]', text: /Pages compared: 1\/2/
    assert_select '#transition-fetch-issues', text: /#{Regexp.escape(@other_url)}.*Wringer.*Wringer request timed out/m
    assert_select '#transition-field-findings', count: 0
    assert_select '#transition-fetch-issues a', text: "Recorded fetch evidence" do |links|
      href = links.first['href']
      assert_includes href, "run_id=#{run.id}"
      assert_includes href, "evidence=recorded-fetch-1"
      get href
    end
    assert_response :success
    assert_select '#transition-recorded-fetches[open] #recorded-fetch-1[open]', text: /Wringer request timed out/
    assert_select '#recorded-fetch-0:not([open])'
    assert_select '#recorded-fetch-1', text: /recorded results, not the current cache/
    assert_select '.transition-primary-action', text: "Inspect recorded failure"
  end

  test "only differing selected-field artifacts are visible with recorded URL source language values and extraction error" do
    run = completed_run(findings: true)
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select '.transition-decision--failed h2', text: "Blocked — stay in Shadow"
    assert_select '#transition-field-findings .transition-field-finding', count: 2
    assert_select '#transition-field-findings', text: /#{Regexp.escape(@other_url)}.*Title.*Source #1719.*fr/m
    assert_select '#recorded-statement-0', text: /"Original title".*"Updated title"/m
    assert_select '#recorded-statement-1', text: /Extraction error:.*InvalidDate/
    assert_select '#transition-field-findings', text: /matching value hidden/, count: 0
    assert_select '#transition-field-findings a[href*="run_id=' + run.id.to_s + '"]', text: "Link to this evidence", count: 2
    assert_select '#transition-field-findings a[href="/sources/1719/edit"]', text: "Edit current source #1719"
    assert_select '.transition-primary-action', text: "Inspect recorded values"
    assert_select '.transition-check-results > li', count: 3
  end

  test "known differences remain blocked even when another page lacks a snapshot" do
    completed_run(missing_wringer: true, findings: true)
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select '.transition-decision--failed h2', text: "Blocked — stay in Shadow"
    assert_select '#transition-fetch-issues', count: 1
    assert_select '#transition-field-findings', text: /#{Regexp.escape(@url)}/
    assert_select '#transition-fetch-issues', text: /#{Regexp.escape(@other_url)}/
    assert_select '#transition-field-findings .transition-field-finding', count: 2
    assert_select '[data-check="statement_delta"] .transition-result--failed'
    assert_select '[data-check="export_diff"] .transition-result--passed'
  end

  test "pending check has one follow action and cannot reuse an old ready decision" do
    completed = completed_run
    pending = Distillator::TransitionRun.request!(website: @website, options: { sample_mode: "all", strictness: "strict" }).run
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select '.transition-decision--running h2', text: "Check in progress — stay in Shadow"
    assert_select '#latest-transition-check', text: /Results below remain from completed run ##{completed.id}/
    assert_select '.transition-primary-action[href="' + distillator_transition_check_path(pending) + '"]', text: "Follow the running check"
    assert_select '.transition-decision--passed, #retry-completed-transition-check', count: 0
    assert_select '.transition-primary-action', text: "Review activation", count: 0
  end

  test "historical evidence stays pinned after a new result and has no activation or retry guidance" do
    old = completed_run(missing_wringer: true)
    completed_run
    get distillator_shadow_report_site_path(@website, run_id: old.id, evidence: "recorded-fetch-1")
    assert_response :success
    assert_select '#historical-transition-run', text: /Historical comparison for run ##{old.id}/
    assert_select '#transition-report-summary', text: /not current activation guidance/
    assert_select '#transition-fetch-issues', text: /Wringer request timed out/
    assert_select '#recorded-fetch-1[open]', text: /Wringer request timed out/
    assert_select '.transition-next-action, #retry-completed-transition-check', count: 0
  end

  test "a website without a completed check shows three neutral unrecorded checks" do
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select '.transition-check-results > li', count: 3
    assert_select '.transition-check-results .transition-result--neutral', text: /Not recorded/, count: 3
    assert_select '.transition-decision--neutral h2', text: "Run checks before activating"

    pending = Distillator::TransitionRun.request!(website: @website).run
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select '.transition-decision--running', text: /Results will appear when all phases finish/
    assert_select '.transition-check-results .transition-result--neutral', count: 3
    assert_select '.transition-primary-action[href="' + distillator_transition_check_path(pending) + '"]'
    assert_select '.transition-decision', text: /previous completed run/, count: 0
  end

  test "an export failure remains visible when selected values pass" do
    run = completed_run
    run.transition_evidences.find_by!(check_kind: "export_diff").update!(status: "failed", export_diff_checked: false,
      details: { reason: "export_diff_failed", error: "Serializer failed" })
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select '[data-check="statement_delta"] .transition-result--passed'
    assert_select '[data-check="export_diff"] .transition-result--failed'
    assert_select '#recorded-phase-export_diff', text: /Failed/
    assert_select '#recorded-phase-export_diff a[href*="run_id=' + run.id.to_s + '"]'
    assert_select '.transition-decision--failed'
  end

  private

  def completed_run(missing_wringer: false, findings: false)
    run = Distillator::TransitionRun.request!(website: @website, options: { sample_mode: "all", strictness: "strict" }).run
    run.execute do
      scope = { representative_webpages: [@url, @other_url], representative_webpage_count: 2,
        publishable_event_page_count: 2, candidate_webpage_count: 2, selection_rule: run.options.selection_rule }
      fetch_rows = [@url, @other_url].map do |url|
        { url: url, fetch_status: "passed", fetch_reason: "ok", http_response_code: 200,
          attempted_condenser_fetch: true, legacy_lookup_status: "ok", comparison_status: "passed", compare_missing: {} }
      end
      if missing_wringer
        fetch_rows.last.merge!(legacy_lookup_status: "unreachable", legacy_lookup_error: "Wringer request timed out",
          comparison_status: "missing", compare_missing: { legacy: true })
      end
      run.transition_evidences.create!(website: @website, url: @url, check_kind: "fetch_parity", status: "checked", checked_at: Time.current,
        details: scope.merge(fetch_basis: "fresh_both", reason: missing_wringer ? "legacy_lookup_unreachable" : "ok",
          fetch_attempted_webpage_count: 2, representative_url_results: fetch_rows))
      artifacts = [{ webpage_url: @url, property_label: "Location", source_id: 1715, language: "fr",
        legacy: "matching value hidden", condenser: "matching value hidden", verdict: "MATCH", severity: "blocker" }]
      if findings
        finding_url = missing_wringer ? @url : @other_url
        artifacts << { webpage_url: finding_url, property_label: "Title", source_id: 1719, language: "fr",
          legacy: "Original title", condenser: "Updated title", verdict: "DIFFERENT_VALUE", severity: "blocker" }
        artifacts << { webpage_url: finding_url, property_label: "Dates", source_id: 1716, language: "fr",
          legacy: "2026-12-01", condenser: nil, condenser_error: { error_type: "InvalidDate", error: "Invalid input" },
          verdict: "PARSE_ERROR", severity: "blocker" }
      end
      state = findings ? "failed" : missing_wringer ? "pending" : "checked"
      run.transition_evidences.create!(website: @website, url: @url, check_kind: "statement_delta", status: state,
        statement_count_delta_acceptable: state == "checked", checked_at: Time.current,
        details: scope.merge(source: "paired_extraction", comparison_basis: "paired_dsl", reason: findings ? "strict_statement_parity_failed" : missing_wringer ? "partial_fetch_failed_before_statement_refresh" : "paired_statements_match",
          compared_webpage_count: missing_wringer ? 1 : 2, statement_artifacts: artifacts,
          statements_compared_count: artifacts.length, critical_statements_failed_count: findings ? 2 : 0,
          representative_url_statement_results: [
            { url: @url, status: findings && missing_wringer ? "failed" : "passed" },
            { url: @other_url, status: missing_wringer ? "inconclusive" : findings ? "failed" : "passed", reason: missing_wringer ? "paired_snapshot_missing" : "paired_statements_match" }
          ]))
      run.transition_evidences.create!(website: @website, url: @url, check_kind: "export_diff", status: "checked",
        export_diff_checked: true, checked_at: Time.current, details: scope.merge(export_compared: true,
          export_basis: "current export vs production-equivalent export"))
    end
    run
  end
end
