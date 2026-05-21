require "test_helper"

class Distillator::ShadowReportsControllerTest < ActionDispatch::IntegrationTest
  test "shadow report renders successfully without fetching" do
    create_shadow_website(name: "Shadow alpha", seedurl: "shadow-alpha")
    create_regular_website(name: "Legacy alpha", seedurl: "legacy-alpha", mode: "legacy")
    create_regular_website(name: "Active alpha", seedurl: "active-alpha", mode: "active")

    assert_read_only_page_does_not_fetch

    get distillator_shadow_report_path

    assert_response :success
    assert_match "Transition Report", @response.body
    assert_match "Legacy sites", @response.body
    assert_match "Shadow sites", @response.body
    assert_match "Active sites", @response.body
    assert_match "Promotable sites", @response.body
    assert_match "Top blockers", @response.body
    assert_match "Failed fetch", @response.body
    assert_includes @response.body, "Use each site row to run a transition check"
    assert_no_cohort_source_requests
  end

  test "shadow report shows navigation link between cache and options" do
    get distillator_shadow_report_path

    assert_response :success
    assert_match %r{/distillator/cache.*?/distillator/shadow_report.*?/options}m, @response.body
  end

  test "shadow report lists shadow sites with summary actions only on the index" do
    website = create_shadow_website(name: "Shadow beta", seedurl: "shadow-beta")
    create_cache_for(website, url: "https://shadow-beta.example/event")

    assert_read_only_page_does_not_fetch

    get distillator_shadow_report_path

    assert_response :success
    assert_match "Shadow beta", @response.body
    assert_match "Production backend", @response.body
    assert_match "Wringer", @response.body
    assert_match "Detail", @response.body
    assert_no_match "Compare Condenser vs Wringer", @response.body
    assert_no_match "Open active cache", @response.body
    assert_no_cohort_source_requests
  end

  test "shadow report shows cohort column filter and lavitrine rows" do
    website = create_shadow_website(name: "Hector Charland", seedurl: "hector-charland-com")
    create_cache_for(
      website,
      url: "https://hector-charland-com.example/event",
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "representative_urls_checked" => true,
        "statement_count_delta_acceptable" => true
      }
    )

    get distillator_shadow_report_path

    assert_response :success
    assert_match "Cohort", @response.body
    assert_match "Current page", @response.body
    assert_match "La Vitrine pipeline", @response.body
    assert_includes @response.body, 'name="cohort"'
    assert_no_cohort_source_requests
  end

  test "shadow report defaults to bounded shadow-only results" do
    30.times do |index|
      create_shadow_website(name: format("Shadow %02d", index), seedurl: "shadow-only-#{index}")
    end
    create_regular_website(name: "Legacy site", seedurl: "legacy-shadow-report", mode: "legacy")
    create_regular_website(name: "Active site", seedurl: "active-shadow-report", mode: "active")

    get distillator_shadow_report_path

    assert_response :success
    assert_match "Shadow 00", @response.body
    assert_no_match %r{<tbody>.*Legacy site.*</tbody>}m, @response.body
    assert_no_match %r{<tbody>.*Active site.*</tbody>}m, @response.body
    assert_match "30 sites matched.", @response.body
    assert_includes @response.body, 'name="limit"'
  end

  test "shadow report supports filters sorting pagination and not checked visibility" do
    review = create_shadow_website(name: "Review queue", seedurl: "review-queue")
    blocked = create_shadow_website(name: "Blocked queue", seedurl: "blocked-queue")
    create_shadow_website(name: "Unknown queue", seedurl: "unknown-queue")
    create_regular_website(name: "Active queue", seedurl: "active-queue", mode: "active")

    create_cache_for(
      review,
      url: "https://review-queue.example/event",
      signals: { "transport_success" => true },
      primary_issue_key: "queue_it",
      primary_issue_label: "Queue-it waiting room",
      primary_issue_severity: "warning",
      health_status: "redirect_changed",
      health_severity: "low",
      redirected: true,
      final_url: "https://review-queue.example/redirected"
    )
    create_cache_for(
      blocked,
      url: "https://blocked-queue.example/event",
      signals: { "transport_success" => false, "content_success" => false, "primary_issue_key" => "timeout", "primary_issue_severity" => "failed" },
      primary_issue_key: "timeout",
      primary_issue_label: "Fetch timeout",
      primary_issue_severity: "failed",
      health_status: "attempt_failed",
      health_severity: "high"
    )

    get distillator_shadow_report_path, params: { status: "review", term: "queue", sort: "website", direction: "asc", limit: "1" }
    follow_redirect! if response.redirect?

    assert_response :success
    assert_match "Review queue", @response.body
    assert_no_match "Blocked queue", @response.body
    assert_no_match "Unknown queue", @response.body
    assert_match "Apply filters", @response.body
    assert_match "Reset filters", @response.body
    assert_match %r{name="limit"[^>]*value="1"}, @response.body

    get distillator_shadow_report_path, params: { status: "not_checked" }

    assert_response :success
    assert_match "Unknown queue", @response.body
    assert_no_match "Active queue", @response.body
    assert_match "Not checked", @response.body
  end

  test "shadow report supports promotable filter" do
    ready = create_shadow_website(name: "Promotable queue", seedurl: "promotable-queue")
    blocked = create_shadow_website(name: "Blocked queue", seedurl: "blocked-promotable-queue")

    create_cache_for(
      ready,
      url: "https://promotable-queue.example/event",
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "statement_count_delta_acceptable" => true,
        "export_diff_checked" => true
      }
    )
    ready.transition_evidences.create!(
      id: next_id,
      url: "https://promotable-queue.example/event",
      check_kind: "statement_delta",
      status: "checked",
      statement_count_delta_acceptable: true,
      checked_at: 1.hour.ago
    )
    ready.transition_evidences.create!(
      id: next_id,
      url: "https://promotable-queue.example/event",
      check_kind: "export_diff",
      status: "checked",
      export_diff_checked: true,
      checked_at: 1.hour.ago
    )
    create_cache_for(
      blocked,
      url: "https://blocked-promotable-queue.example/event",
      signals: { "transport_success" => false, "content_success" => false },
      health_status: "attempt_failed",
      health_severity: "high",
      primary_issue_key: "timeout",
      primary_issue_label: "Fetch timeout",
      primary_issue_severity: "failed"
    )

    get distillator_shadow_report_path, params: { promotable: "yes", term: "queue" }

    assert_response :success
    assert_includes @response.body, 'name="promotable"'
    assert_match "Promotable queue", @response.body
    assert_no_match "Blocked queue", @response.body

    get distillator_shadow_report_path, params: { promotable: "no", term: "queue" }

    assert_response :success
    assert_match "Blocked queue", @response.body
    assert_no_match "Promotable queue", @response.body
  end

  test "shadow report detail page renders without fetching" do
    website = create_shadow_website(name: "Detail site", seedurl: "detail-site")
    create_cache_for(website, url: "https://detail-site.example/event")

    assert_read_only_page_does_not_fetch

    get distillator_shadow_report_site_path(website)

    assert_response :success
    assert_match "Transition Report Detail", @response.body
    assert_match "Decision", @response.body
    assert_match "Current checks", @response.body
    assert_match "Primary blocker", @response.body
    assert_match "Next action", @response.body
    assert_match "Checked scope", @response.body
    assert_match "Transition evidence", @response.body
    assert_match "Fetch parity", @response.body
    assert_match %r{Decision.*Current checks}m, @response.body
  end

  test "shadow report row shows run transition check for shadow sites with missing evidence" do
    website = create_shadow_website(name: "Blocked evidence", seedurl: "blocked-evidence")
    create_cache_for(website, url: "https://blocked-evidence.example/event")

    get distillator_shadow_report_path

    assert_response :success
    assert_match "Run transition check", @response.body
    assert_match "Statement check not yet recorded", @response.body
  end

  test "shadow report detail shows promote to active when evidence is fresh and passing" do
    website = create_shadow_website(name: "Ready detail", seedurl: "ready-detail")
    url = "https://ready-detail.example/event"
    create_cache_for(
      website,
      url: url,
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "statement_count_delta_acceptable" => true,
        "export_diff_checked" => true
      }
    )
    website.transition_evidences.create!(id: next_id, url: url, check_kind: "fetch_parity", status: "checked", checked_at: 1.hour.ago)
    website.transition_evidences.create!(id: next_id, url: url, check_kind: "statement_delta", status: "checked", statement_count_delta_acceptable: true, checked_at: 1.hour.ago)
    website.transition_evidences.create!(id: next_id, url: url, check_kind: "export_diff", status: "checked", export_diff_checked: true, checked_at: 1.hour.ago)

    get distillator_shadow_report_site_path(website)

    assert_response :success
    assert_match "Promote to active", @response.body
    assert_match "Safe to promote", @response.body
    assert_match %r{<strong>Export</strong> — Passed}m, @response.body
  end

  test "shadow report detail separates blocked activation from passing export and shows failed statement explanation" do
    website = create_shadow_website(name: "Blocked detail", seedurl: "blocked-detail")
    url = "https://blocked-detail.example/event"
    create_cache_for(
      website,
      url: url,
      signals: { "transport_success" => true, "content_success" => true }
    )
    webpage = website.webpages.find_by!(url: url)
    source = Source.create!(
      algorithm_value: "manual=Blocked detail dates",
      selected: true,
      selected_by: "test",
      language: "fr",
      render_js: false,
      property: properties(:six),
      website: website
    )
    statement = Statement.create!(
      cache: "",
      status: "problem",
      status_origin: "shadow_reports_controller_test",
      cache_refreshed: 1.hour.ago,
      cache_changed: 1.hour.ago,
      source: source,
      webpage: webpage,
      selected_individual: true
    )
    website.transition_evidences.create!(
      id: next_id,
      url: url,
      check_kind: "fetch_parity",
      status: "checked",
      checked_at: 1.hour.ago
    )
    website.transition_evidences.create!(
      id: next_id,
      url: url,
      check_kind: "statement_delta",
      status: "failed",
      statement_delta: 1,
      statement_count_delta_acceptable: false,
      checked_at: 1.hour.ago,
      details: {
        reason: "statement_refresh_failed",
        representative_webpages: [url],
        representative_webpage_count: 1,
        candidate_webpage_count: 4,
        selection_rule: "Event pages first, ordered by archive date",
        statements_refreshed_count: 1,
        statements_failed_count: 1,
        failing_statement_ids: [statement.id],
        failing_statements: [{ id: statement.id, webpage_url: url, source: "Dates / fr" }],
        refresh_errors: ["DSL returned blank result"]
      }
    )
    website.transition_evidences.create!(
      id: next_id,
      url: url,
      check_kind: "export_diff",
      status: "checked",
      export_diff_checked: true,
      checked_at: 1.hour.ago,
      details: { export_compared: true, export_basis: "current export vs production-equivalent export" }
    )

    get distillator_shadow_report_site_path(website)

    assert_response :success
    assert_match "Blocked", @response.body
    assert_match %r{<strong>Export</strong> — Passed}m, @response.body
    assert_match "Statement refresh failed for 1 statement.", @response.body
    assert_match "Statement ID: #{statement.id}", @response.body
    assert_match "Source: Dates / fr", @response.body
    assert_match "Reason: DSL returned blank result", @response.body
    assert_match "Open the statement trace and fix the source before activating.", @response.body
    assert_match "Representative webpages checked: 1 of 4", @response.body
    assert_match "This check used a limited sample of representative webpages.", @response.body
    assert_match "Do not activate yet", @response.body
  end

  test "shadow report detail shows statements not evaluated when fetch failed before statement refresh" do
    website = create_shadow_website(name: "Fetch blocked detail", seedurl: "fetch-blocked-detail")
    url = "https://fetch-blocked-detail.example/event"
    create_cache_for(
      website,
      url: url,
      signals: { "transport_success" => false, "content_success" => false },
      health_status: "empty_body",
      health_severity: "high",
      primary_issue_key: "empty_body",
      primary_issue_label: "Empty body",
      primary_issue_severity: "failed"
    )
    website.transition_evidences.create!(
      id: next_id,
      url: url,
      check_kind: "statement_delta",
      status: "pending",
      checked_at: 1.hour.ago,
      details: {
        reason: "fetch_failed_before_statement_refresh",
        representative_webpages: [url],
        representative_webpage_count: 1,
        candidate_webpage_count: 1,
        selection_rule: "Event pages first, ordered by archive date",
        statements_refreshed_count: 0,
        statements_failed_count: 0
      }
    )
    website.transition_evidences.create!(
      id: next_id,
      url: url,
      check_kind: "export_diff",
      status: "checked",
      export_diff_checked: true,
      checked_at: 1.hour.ago,
      details: { export_compared: true, export_basis: "current export vs production-equivalent export" }
    )

    get distillator_shadow_report_site_path(website)

    assert_response :success
    assert_match "Statements</strong> — Not evaluated", @response.body
    assert_match "Fetch failed before statements could be refreshed.", @response.body
    assert_match "Fix the fetch/cache failure first, then rerun the transition check.", @response.body
    assert_match %r{<strong>Export</strong> — Passed}m, @response.body
    assert_no_match "failed on 0 representative webpages", @response.body
    assert_operator @response.body.scan("Cannot promote yet").count, :<=, 1
  end

  test "fetch blocker shows direct cache links and audit uses causal labels" do
    website = create_shadow_website(name: "Fetch links detail", seedurl: "fetch-links-detail")
    url = "https://www.dansedanse.ca/fr/spectacles/message-in-a-bottle-sting-kate-prince"
    cache = create_cache_for(
      website,
      url: url,
      signals: {
        "transport_success" => true,
        "content_success" => false,
        "policy_action" => "abort_update",
        "content_rejected" => true,
        "content_type" => "html",
        "fetched_body_state" => "non_empty",
        "fetched_body_bytes" => 2048,
        "stored_body_state" => "not_stored",
        "stored_body_bytes" => 0,
        "storage_decision" => "abort_update",
        "cache_body_empty_after_abort" => true,
        "primary_issue_match" => {
          "source" => "body_text",
          "pattern" => "Une erreur est survenue",
          "snippet" => "Une erreur est survenue. Veuillez reessayer."
        }
      },
      health_status: "content_rejected",
      health_severity: "high",
      primary_issue_key: "generic_error_text",
      primary_issue_label: "Generic error text observed",
      primary_issue_severity: "failed"
    )
    website.transition_evidences.create!(
      id: next_id,
      url: url,
      check_kind: "fetch_parity",
      status: "failed",
      checked_at: 1.hour.ago,
      primary_issue_key: "generic_error_text",
      details: { reason: "cache_health_failed" }
    )
    website.transition_evidences.create!(
      id: next_id,
      url: url,
      check_kind: "statement_delta",
      status: "pending",
      checked_at: 1.hour.ago,
      details: {
        reason: "fetch_failed_before_statement_refresh",
        representative_webpages: [url],
        representative_webpage_count: 1,
        candidate_webpage_count: 1,
        selection_rule: "Event pages first, ordered by archive date",
        statements_refreshed_count: 0,
        statements_failed_count: 0
      }
    )
    website.transition_evidences.create!(
      id: next_id,
      url: url,
      check_kind: "export_diff",
      status: "pending",
      checked_at: 1.hour.ago,
      details: {
        reason: "fetch_failed_before_export_comparison",
        representative_webpages: [url],
        representative_webpage_count: 1,
        candidate_webpage_count: 1,
        export_compared: false,
        export_basis: "current export vs production-equivalent export"
      }
    )

    get distillator_shadow_report_site_path(website)

    assert_response :success
    assert_match %r{all websites</a>\s*\|\s*<a[^>]+href="/websites/#{website.id}">#{Regexp.escape(website.name)}</a>\s*\|\s*<a[^>]+href="/webpages"}, @response.body
    assert_match "Fetch/cache failed for the representative URL.", @response.body
    assert_match "generic_error_text", @response.body
    assert_match "High: Generic error text observed", @response.body
    assert_match "Fetch result: HTTP 200 HTML", @response.body
    assert_match "Storage decision: abort_update", @response.body
    assert_match "Stored cache body: empty because the update was aborted", @response.body
    assert_match "Latest attempt", @response.body
    assert_match "Latest successful refresh", @response.body
    assert_match "Open failed cache result", @response.body
    assert_match "Compare Condenser vs Wringer", @response.body
    assert_match "Open active Wringer cache", @response.body
    assert_match "Open Condenser cache", @response.body
    assert_match CGI.escape(url), @response.body
    assert_match distillator_cache_path(cache), @response.body
    assert_match "not evaluated", @response.body
    assert_match "blocked by fetch", @response.body
    assert_no_match %r{Statements</td>\s*<td>missing</td>}m, @response.body
    assert_no_match %r{Export</td>\s*<td>missing</td>}m, @response.body
  end

  test "diagnostics is read only and does not render transition check button or trailing separator" do
    website = create_shadow_website(name: "Diagnostics detail", seedurl: "diagnostics-detail")
    url = "https://diagnostics-detail.example/event"
    create_cache_for(website, url: url)

    get distillator_shadow_report_site_path(website)

    assert_response :success
    diagnostics_html = @response.body[%r{<summary>Diagnostics</summary>.*?</details>}m]
    assert_not_nil diagnostics_html
    assert_no_match "Run transition check", diagnostics_html
    assert_no_match %r{\|\s*</p>}m, diagnostics_html
    assert_equal 1, @response.body.scan("Run transition check").size
  end

  test "transition detail suppresses empty operator context status and actions" do
    website = create_shadow_website(name: "Context detail", seedurl: "context-detail")
    create_cache_for(website, url: "https://context-detail.example/event")

    get distillator_shadow_report_site_path(website)

    assert_response :success
    assert_no_match 'data-context-domain="status"', @response.body
    assert_no_match 'data-context-domain="actions"', @response.body
  end

  test "shadow report detail keeps cache links in diagnostics and rollout events in audit" do
    website = create_shadow_website(name: "IA detail", seedurl: "ia-detail")
    url = "https://ia-detail.example/event"
    create_cache_for(website, url: url)
    website.rollout_events.create!(from_mode: "legacy", to_mode: "shadow", reason: "test", readiness_snapshot: { warnings: ["manual review"] })

    get distillator_shadow_report_site_path(website)

    assert_response :success
    assert_match %r{<summary>Diagnostics</summary>.*Cache links:}m, @response.body
    assert_match %r{<summary>Audit</summary>.*Recent rollout events}m, @response.body
  end

  test "shadow report detail explains export generation failures and rdf diff counts" do
    website = create_shadow_website(name: "Export detail", seedurl: "export-detail")
    url = "https://export-detail.example/event"
    create_cache_for(
      website,
      url: url,
      signals: { "transport_success" => true, "content_success" => true }
    )
    website.transition_evidences.create!(
      id: next_id,
      url: url,
      check_kind: "export_diff",
      status: "failed",
      export_diff_status: "failed",
      rdf_added_count: 2,
      rdf_removed_count: 1,
      checked_at: 1.hour.ago,
      details: { reason: "export_generation_failed" }
    )

    get distillator_shadow_report_site_path(website)

    assert_response :success
    assert_match "Export could not be generated.", @response.body
    assert_match "RDF added: 2", @response.body
    assert_match "RDF removed: 1", @response.body
  end

  test "active transition report detail shows rollback guidance without fetching" do
    website = create_regular_website(name: "Active detail", seedurl: "active-detail", mode: "active")

    assert_read_only_page_does_not_fetch

    get distillator_shadow_report_site_path(website)

    assert_response :success
    assert_match "Rollback path", @response.body
    assert_match "Set rollout mode to Legacy in website options.", @response.body
    assert_match "Wringer becomes production backend.", @response.body
    assert_match "Condenser cache remains available for inspection.", @response.body
  end

  test "shadow report filters to la vitrine cohort and other cohort classes" do
    lavitrine = create_shadow_website(name: "Hector Charland", seedurl: "hector-charland-com")
    other = create_shadow_website(name: "Outside cohort", seedurl: "outside-cohort")

    create_cache_for(
      lavitrine,
      url: "https://hector-charland-com.example/event",
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "representative_urls_checked" => true,
        "statement_count_delta_acceptable" => true
      }
    )
    create_cache_for(
      other,
      url: "https://outside-cohort.example/event",
      signals: {
        "transport_success" => true,
        "content_success" => true
      }
    )

    get distillator_shadow_report_path, params: { cohort: "lavitrine_pipeline" }

    assert_response :success
    assert_match "Hector Charland", @response.body
    assert_no_match "Outside cohort", @response.body

    get distillator_shadow_report_path, params: { cohort: "other" }

    assert_response :success
    assert_match "Outside cohort", @response.body
    assert_no_match "Hector Charland", @response.body
  end

  test "shadow report does not mutate rollout mode" do
    website = create_shadow_website(name: "No mutation", seedurl: "no-mutation")

    get distillator_shadow_report_path

    assert_response :success
    assert_equal "shadow", website.reload.distillator_mode
  end

  test "transition report row includes options link and priority subset card" do
    website = create_shadow_website(name: "Priority shadow", seedurl: "hector-charland-com")
    create_cache_for(website, url: "https://hector-charland-com.example/event")

    get distillator_shadow_report_path

    assert_response :success
    assert_match "Priority sites", @response.body
    assert_match options_path, @response.body
    assert_match "Detail", @response.body
    assert_no_match "Compare Condenser vs Wringer", @response.body
    assert_no_match "Open active cache", @response.body
  end

  test "shadow report clamps the requested limit and keeps empty state rendering" do
    101.times do |index|
      create_shadow_website(name: format("Clamp %03d", index), seedurl: "clamp-#{index}")
    end

    get distillator_shadow_report_path, params: { limit: "999", term: "not-a-real-site" }
    follow_redirect! if response.redirect?

    assert_response :success
    assert_match %r{name="limit"[^>]*value="100"}, @response.body
    assert_match "No sites found.", @response.body
  end

  test "transition report supports rollout mode filter" do
    create_shadow_website(name: "Shadow site", seedurl: "shadow-site")
    create_regular_website(name: "Active site", seedurl: "active-site", mode: "active")

    get distillator_shadow_report_path, params: { mode: "active" }

    assert_response :success
    assert_includes @response.body, 'name="mode"'
    assert_match "Active site", @response.body
    assert_no_match %r{<tbody>.*Shadow site.*</tbody>}m, @response.body
  end

  private

  def create_shadow_website(name:, seedurl:)
    create_regular_website(name: name, seedurl: seedurl, mode: "shadow")
  end

  def create_regular_website(name:, seedurl:, mode:)
    Website.create!(
      id: next_id,
      name: name,
      seedurl: seedurl,
      graph_name: "https://#{seedurl}.example/graph",
      default_language: "en",
      distillator_mode: mode
    )
  end

  def create_cache_for(website, url:, signals: { "transport_success" => true, "content_success" => true }, primary_issue_key: nil, primary_issue_label: nil, primary_issue_severity: nil, health_status: "healthy", health_severity: "ok", redirected: false, final_url: nil, html: "<html>cached</html>", body: "<html>cached</html>")
    website.webpages.create!(
      id: next_id,
      url: url,
      language: "en",
      rdf_uri: "adr:#{website.seedurl}",
      rdfs_class: rdfs_classes(:one)
    )

    Distillator::FetchCache.create!(
      id: next_id,
      uri_key: CGI.escape(url),
      normalized_url: url,
      name: website.name,
      html: html,
      body: body,
      http_response_code: 200,
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: signals.merge(
        "primary_issue_key" => primary_issue_key,
        "primary_issue_label" => primary_issue_label,
        "primary_issue_severity" => primary_issue_severity
      ).compact,
      hints: Array(primary_issue_key).compact,
      final_url: final_url || url,
      redirect_chain: redirected ? [url, final_url || url] : [],
      redirected: redirected,
      health_status: health_status,
      health_severity: health_severity,
      primary_issue_key: primary_issue_key,
      primary_issue_label: primary_issue_label,
      primary_issue_severity: primary_issue_severity
    )
  end

  def next_id
    @next_id ||= 1_200_000_000 + ((Process.pid % 10_000) * 100_000)
    @next_id += 1
  end

  def assert_read_only_page_does_not_fetch
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never
  end

  def assert_no_cohort_source_requests
    WebMock.assert_not_requested(:any, Distillator::Cohorts::LavitrinePipeline.query_url)
  end
end
