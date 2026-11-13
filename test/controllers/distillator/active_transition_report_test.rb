require "test_helper"

class Distillator::ActiveTransitionReportTest < ActionDispatch::IntegrationTest
  setup do
    Distillator::WringerEndpoint.stubs(:current).returns(Distillator::WringerEndpoint::Result.new(
      compatibility_base_url: "https://compat.example", legacy_lookup_base_url: "https://wringer.example",
      state: :remote_configured, status_label: "Remote configured", status_detail: "Test endpoint"))
    @website = Website.create!(name: "Vieux Noranda", seedurl: "petittheatre-org", default_language: "fr",
      graph_name: "https://example.org/report", distillator_mode: "shadow")
    @url = "https://petittheatre.example/event"
    @website.webpages.create!(url: @url, language: "fr", rdf_uri: "rdf:report-event", rdfs_class: rdfs_classes(:one))
    @cache = Distillator::FetchCache.create!(uri_key: CGI.escape(@url), normalized_url: @url,
      html: "<title>Théâtre</title>", body: "<title>Théâtre</title>", http_response_code: 200,
      scrape_date: 2.minutes.ago, successful_refresh: 2.minutes.ago, headers: {}, final_url: @url,
      signals: { transport_success: true, content_success: true, fetch_backend: "native", network_status: "ok", content_type: "html" })
    scope = { representative_webpages: [@url], representative_webpage_count: 1, publishable_event_page_count: 9 }
    @website.transition_evidences.create!(url: @url, check_kind: "fetch_parity", status: "checked", checked_at: 1.minute.ago,
      details: scope.merge(reason: "review_needed_difference", compare_summary: { review_needed_diffs: ["html_sha256"] },
        representative_url_results: [{ url: @url, fetch_status: "passed", fetch_reason: "ok", legacy_lookup_status: "ok",
          comparison_status: "review", compare_summary: { review_needed_diffs: ["html_sha256"] } }]))
    @website.transition_evidences.create!(url: @url, check_kind: "statement_delta", status: "checked", checked_at: 1.minute.ago,
      statement_count_delta_acceptable: true, details: scope.merge(source: "paired_extraction", comparison_basis: "paired_dsl",
        statements_compared_count: 175, statements_refreshed_count: 0, statements_failed_count: 0,
        representative_url_statement_results: [{ url: @url, status: "passed", reason: "paired_statements_match" }]))
    @website.transition_evidences.create!(url: @url, check_kind: "export_diff", status: "checked", checked_at: 1.minute.ago,
      export_diff_checked: true, details: scope.merge(export_compared: true,
        export_basis: "current export vs production-equivalent export", representative_url_export_results: [{ url: @url, status: "checked" }]))
    @completed = publish_transition_fixture(@website, at: 1.minute.ago)
    result = Distillator::RolloutTransition.call(website: @website, to_mode: "active", review: true, reason: "Reviewed the HTML-only differences")
    assert result.success?, result.errors.inspect
    @activation_snapshot = @website.rollout_events.last.readiness_snapshot.deep_dup
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::TransitionCheckRunner.expects(:call).never
    Distillator::RefreshRunner.expects(:call).never
    ExportArtsdataService.expects(:call).never
  end

  test "running recheck does not relabel the active site or contaminate completed results" do
    run = request_run
    run.update!(status: "running", started_at: Time.current)
    run.transition_evidences.create!(website: @website, url: @url, check_kind: "fetch_parity", status: "failed", checked_at: Time.current)
    @website.update_column(:transition_check_requested_at, 20.days.ago)

    assert_no_difference ["Statement.count", "Distillator::TransitionRun.count", "Distillator::RolloutEvent.count"] do
      get distillator_shadow_report_site_path(@website)
    end

    assert_response :success
    assert_select '#transition-report-summary strong', text: "Active on Condenser"
    assert_select '#latest-transition-check strong', text: "Run ##{run.id}: Running"
    assert_select '#latest-transition-check', text: /Results below remain from completed run ##{@completed.id}/
    assert_includes response.body, "Wait for run ##{run.id} to finish"
    assert_select 'strong', text: "Reviewed and accepted for this activation."
    assert_not_includes response.body, "Do not activate yet"
    assert_not_includes response.body, "Safety:</strong> Unsafe"
    assert_not_includes response.body, "Run a new transition batch check"
    assert_not_includes response.body, "Review checklist"
    assert_select 'td:nth-child(2)', text: "Passed"
    assert_equal "active", @website.reload.distillator_mode
  end

  test "paired counts healthy cache links and backend names are accurate without duplicate evidence" do
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_includes response.body, "Source comparisons: 175"
    assert_not_includes response.body, "Statements refreshed"
    assert_includes response.body, "Serializer compatibility using stored data in this environment"
    assert_not_includes response.body, "Raw legacy transition evidence"
    assert_select 'summary', text: "Statements details", count: 1
    assert_select 'a', text: "Open failed cache result", count: 0
    assert_select 'a', text: "Open active Wringer cache", count: 0
    assert_select 'a[href*="/condenser/cache?"]', text: "Open active Condenser cache"
    assert_select 'a[href*="https://wringer.example/"]', text: "Inspect legacy Wringer"
    assert_select 'a[href*="publishable=true"][href*="scope=all"]', text: "Inspect publishable event pages"
    assert_select 'td:nth-child(4)' do |cells|
      assert_match /\AReview\s+Fields: HTML body\z/i, cells.first.text.squish
    end
    assert_select 'details.rollout-audit-details:not([open]) summary', text: "Warnings accepted at activation"
    assert_includes response.body, "Reviewed the HTML-only differences"
    assert_equal @activation_snapshot, @website.rollout_events.last.readiness_snapshot
  end

  test "failed recheck keeps the previous reviewed comparison and activation intact" do
    run = request_run
    run.update!(status: "failed", completed_at: Time.current, error_message: "Check timed out")
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select '#latest-transition-check strong', text: "Run ##{run.id} failed:"
    assert_select '#latest-transition-check', text: /Check timed out/
    assert_select 'strong', text: "Reviewed and accepted for this activation."
    assert_includes response.body, "Inspect failed run ##{run.id}"
    assert_not_includes response.body, "Do not activate yet"
    assert_equal "active", @website.reload.distillator_mode
  end

  test "new completed failures require attention and never inherit the old acceptance" do
    publish_recheck(statement_status: "failed")
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select 'strong', text: "Comparison has blocking differences."
    assert_select 'strong', text: "Reviewed and accepted for this activation.", count: 0
    assert_includes response.body, "Findings in completed comparison"
    assert_includes response.body, "Investigate the differences in the latest comparison."
    assert_not_includes response.body, "Do not activate yet"
    assert_select 'a', text: "Open failed cache result", count: 0
    assert_equal "active", @website.reload.distillator_mode
  end

  test "new passing comparison replaces the old result without inheriting its manual review" do
    publish_recheck
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select 'strong', text: "Comparison passed."
    assert_select 'strong', text: "Reviewed and accepted for this activation.", count: 0
    assert_not_includes response.body, "Review before activating"
    assert_equal "active", @website.reload.distillator_mode
    assert_not Distillator::ShadowSiteSummary.call(website: @website, cache: @cache).promotable
  end

  test "post activation fetch failure is visible without rewriting the accepted comparison" do
    @cache.update!(scrape_date: 1.second.from_now, signals: { transport_success: false, content_success: false, fetch_backend: "native" })
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select '#transition-report-summary .cache-page-notice strong', text: "Latest observed fetch failed"
    assert_select 'strong', text: "Reviewed and accepted for this activation."
    assert_select 'a', text: "Open failed cache result"
    assert_includes response.body, "Inspect the latest failed fetch"
    assert_equal @activation_snapshot, @website.rollout_events.last.readiness_snapshot
  end

  test "rollback to Legacy during a running recheck changes the backend and does not suggest promotion" do
    run = request_run
    run.update!(status: "running", started_at: Time.current)
    rollback = Distillator::RolloutTransition.call(website: @website, to_mode: "legacy", reason: "Revert to Wringer")
    assert rollback.success?
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select '#transition-report-summary strong', text: "Legacy Wringer active"
    assert_select '#latest-transition-check strong', text: "Run ##{run.id}: Running"
    assert_includes response.body, "Move to Shadow before considering activation."
    assert_select 'strong', text: "Reviewed and accepted for this activation.", count: 0
    assert_select 'a', text: "Open active Wringer cache"
    assert_select 'a', text: "Open active Condenser cache", count: 0
    assert_not_includes response.body, "Safe to promote"
    assert_not_includes response.body, "Review checklist"
    assert_equal :wringer, Distillator::FetchMode.rollout_resolution_object(website: @website.reload).active_backend
  end

  test "rollback to Shadow requires a new explicit review rather than reusing the old activation" do
    assert Distillator::RolloutTransition.call(website: @website, to_mode: "shadow").success?
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_includes response.body, "Review before activating"
    assert_select 'strong', text: "Reviewed and accepted for this activation.", count: 0
    assert_select 'a', text: "Open active Wringer cache"
    assert_equal :wringer, Distillator::FetchMode.rollout_resolution_object(website: @website.reload).active_backend
    rejected = Distillator::RolloutTransition.call(website: @website, to_mode: "active")
    assert_not rejected.success?
    assert_equal "shadow", @website.reload.distillator_mode
    accepted = Distillator::RolloutTransition.call(website: @website, to_mode: "active", review: true, reason: "Reviewed again after rollback")
    assert accepted.success?, accepted.errors.inspect
    get distillator_shadow_report_site_path(@website)
    assert_select '#transition-report-summary', text: /Reviewed again after rollback/
    assert_select 'strong', text: "Reviewed and accepted for this activation."
    assert_equal :condenser, Distillator::FetchMode.rollout_resolution_object(website: @website.reload).active_backend
  end

  test "a completed recheck after rollback never activates Legacy or authorizes skipping Shadow" do
    assert Distillator::RolloutTransition.call(website: @website, to_mode: "legacy").success?
    publish_recheck
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select '#transition-report-summary strong', text: "Legacy Wringer active"
    assert_select 'strong', text: "Comparison passed."
    assert_not_includes response.body, "Safe to promote"
    assert_not Distillator::ShadowSiteSummary.call(website: @website, cache: @cache).promotable
    direct = Distillator::RolloutTransition.call(website: @website, to_mode: "active")
    assert_not direct.success?
    assert_includes direct.errors, "Direct legacy to active promotion is blocked"
    assert_equal "legacy", @website.reload.distillator_mode
  end

  test "configuration changes and exact reversions distinguish historical approval from current validation" do
    original_graph = @website.graph_name
    @website.update!(graph_name: "https://example.org/changed-graph")
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select 'strong', text: "Reviewed and accepted for this activation."
    assert_select '#transition-report-summary', text: /Source configuration changed since the last check/
    assert_not Distillator::WebsiteOperationStatus.new(website: @website).accepted_comparison?
    get website_path(@website)
    assert_select '#website-transition strong', text: "Reviewed and accepted for this activation."
    assert_select '#website-batch-jobs-transition', text: /Source configuration changed since the last check/

    @website.update!(graph_name: original_graph)
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_not_includes response.body, "Source configuration changed since the last check"
    assert Distillator::WebsiteOperationStatus.new(website: @website).accepted_comparison?
    assert_equal "active", @website.reload.distillator_mode
  end

  test "requested all page strict scope is distinct from the previous completed standard sample" do
    run = Distillator::TransitionRun.request!(website: @website, options: { sample_mode: "all", strictness: "strict" }).run
    get distillator_shadow_report_site_path(@website)
    assert_response :success
    assert_select '#latest-transition-check', text: /All publishable event pages/
    assert_select '#latest-transition-check', text: /Strict: differences in any selected field block activation/
    assert_includes response.body, "Field comparison: Standard: core field differences block; other differences warn"
    assert_select 'strong', text: "Reviewed and accepted for this activation."
    assert_equal "queued", run.reload.status
    assert_equal "active", @website.reload.distillator_mode
  end

  test "a pinned report retains the requested run after a newer comparison and never offers historical activation" do
    newer = publish_recheck(statement_status: "failed")
    @website.update!(distillator_mode: "shadow")
    get distillator_shadow_report_site_path(@website, run_id: @completed.id)
    assert_response :success
    assert_select '#historical-transition-run', text: /Historical comparison for run ##{@completed.id}/
    assert_select '#transition-report-summary', text: /Completed transition run:\s*##{@completed.id}/
    assert_select '#transition-report-summary', text: /Current mode:\s*Shadow/
    assert_select '#transition-url-diagnostics td:nth-child(5)', text: /\APassed\b/
    assert_not_includes response.body, "Review checklist"
    assert_not_includes response.body, "Safe to promote"

    get distillator_shadow_report_site_path(@website, run_id: newer.id)
    assert_response :success
    assert_select '#historical-transition-run', count: 0
    assert_select '#transition-report-summary', text: /Completed transition run:\s*##{newer.id}/
    assert_select '#transition-url-diagnostics td:nth-child(5)', text: /\AFailed\b/
  end

  test "report selection cannot read a different website's run" do
    other = websites(:two)
    get distillator_shadow_report_site_path(other, run_id: @completed.id)
    assert_response :not_found
  end

  test "an unfinished or failed explicit run opens its own status instead of another run's evidence" do
    run = request_run
    get distillator_shadow_report_site_path(@website, run_id: run.id)
    assert_redirected_to distillator_transition_check_path(run)
    run.fail!("Could not finish")
    get distillator_shadow_report_site_path(@website, run_id: run.id)
    assert_redirected_to distillator_transition_check_path(run)
  end

  test "performance details stay collapsed and belong to the selected completed run" do
    export = @completed.transition_evidences.find_by!(check_kind: "export_diff")
    export.update!(details: export.details.merge("performance" => {
      total_ms: 10000, phases_ms: { fetch: 1000, statements: 8000, export: 1000 },
      reconciliation: { lookups: 90, http_requests: 12, cache_hits: 78, http_ms: 7000, errors: 0 },
      slowest_sources: [{ field: "Location", source_id: 12, executions: 18, extraction_ms: 100, formatting_ms: 7000 }]
    }))
    get distillator_shadow_report_site_path(@website, run_id: @completed.id)
    assert_response :success
    assert_select '#transition-performance:not([open]) summary', text: "Where time was spent"
    assert_select '#transition-performance', text: /12 HTTP requests/
    assert_select '#transition-performance', text: /78 reused responses/
    assert_select '#transition-performance', text: /Location/
  end

  test "a ready strict report has one decision and high evidence confidence despite diagnostic notes" do
    assert Distillator::RolloutTransition.call(website: @website, to_mode: "shadow").success?
    run = publish_recheck(check_options: { sample_mode: "all", strictness: "strict" })
    get distillator_shadow_report_site_path(@website, run_id: run.id)
    assert_response :success
    summary = assert_select('#transition-report-summary').first
    assert_equal 1, summary.text.scan("Safe to promote").length
    assert_equal 1, summary.text.scan("Next step:").length
    assert_select '#transition-report-summary > p', text: /Data field comparison:\s*Strict/
    assert_select 'h2', text: "Decision", count: 0
    assert_select '#transition-report-audit', text: /Evidence confidence:\s*High/
    assert_select '#transition-report-audit', text: /Cache diagnostics policy:\s*Review known destination changes/
    assert_not_includes response.body, "Operator mode"
    assert_select '#transition-url-diagnostics td:nth-child(4)', text: "Passed with diagnostic notes"
    assert_select '#transition-url-diagnostics .sources-secondary-text', text: "Metadata only", count: 0
    assert_equal "shadow", @website.reload.distillator_mode
    assert_equal @activation_snapshot, @website.rollout_events.find_by(to_mode: "active").readiness_snapshot
  end

  test "the export explanation renders its source URL once" do
    get distillator_shadow_report_site_path(@website, run_id: @completed.id)
    export_details = assert_select('details[data-check-kind="export_diff"]').first
    assert_equal 1, export_details.text.scan(@url).length
  end

  private

  def request_run
    Distillator::TransitionRun.request!(website: @website).run
  end

  def publish_recheck(statement_status: "checked", check_options: {})
    run = Distillator::TransitionRun.request!(website: @website, options: check_options).run
    run.execute do
      @completed.transition_evidences.each do |record|
        attrs = record.attributes.except("id", "created_at", "updated_at", "transition_run_id")
        if record.check_kind == "fetch_parity"
          attrs["details"] = attrs["details"].merge("reason" => "metadata_only_difference",
            "representative_url_results" => [{ url: @url, fetch_status: "passed", legacy_lookup_status: "ok", comparison_status: "metadata_only" }])
        elsif record.check_kind == "statement_delta"
          attrs["status"] = statement_status
          attrs["statement_count_delta_acceptable"] = statement_status == "checked"
          if statement_status == "failed"
            attrs["details"] = attrs["details"].merge("representative_url_statement_results" => [
              { url: @url, status: "failed", reason: "paired_statement_mismatch" }
            ])
          end
        end
        run.transition_evidences.create!(attrs.merge("checked_at" => Time.current))
      end
    end
    run
  end
end
