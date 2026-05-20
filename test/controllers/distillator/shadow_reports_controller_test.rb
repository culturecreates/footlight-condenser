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
    assert_includes @response.body, "bin/rails distillator:transition:check[website_id]"
    assert_no_cohort_source_requests
  end

  test "shadow report shows navigation link between cache and options" do
    get distillator_shadow_report_path

    assert_response :success
    assert_match %r{/distillator/cache.*?/distillator/shadow_report.*?/options}m, @response.body
  end

  test "shadow report lists shadow sites shows production backend and includes compare link when available" do
    website = create_shadow_website(name: "Shadow beta", seedurl: "shadow-beta")
    create_cache_for(website, url: "https://shadow-beta.example/event")

    assert_read_only_page_does_not_fetch

    get distillator_shadow_report_path

    assert_response :success
    assert_match "Shadow beta", @response.body
    assert_match "Production backend", @response.body
    assert_match "Wringer", @response.body
    assert_match "Compare Condenser vs Wringer", @response.body
    assert_match "Open active cache", @response.body
    assert_no_cohort_source_requests
  end

  test "shadow report shows cohort column filter and la vitrine summary cards" do
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
    assert_match "La Vitrine total", @response.body
    assert_match "La Vitrine pipeline", @response.body
    assert_includes @response.body, 'name="cohort"'
    assert_no_cohort_source_requests
  end

  test "shadow report includes legacy shadow and active websites by default" do
    create_shadow_website(name: "Shadow only", seedurl: "shadow-only")
    create_regular_website(name: "Legacy site", seedurl: "legacy-shadow-report", mode: "legacy")
    create_regular_website(name: "Active site", seedurl: "active-shadow-report", mode: "active")

    get distillator_shadow_report_path

    assert_response :success
    assert_match "Shadow only", @response.body
    assert_match "Legacy site", @response.body
    assert_match "Active site", @response.body
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

    get distillator_shadow_report_path, params: { status: "review", term: "queue", sort: "website", direction: "asc", per_page: "1" }
    follow_redirect! if response.redirect?

    assert_response :success
    assert_match "Review queue", @response.body
    assert_no_match "Blocked queue", @response.body
    assert_no_match "Unknown queue", @response.body
    assert_match "Apply filters", @response.body
    assert_match "Reset filters", @response.body
    assert_match "All sites Blocked", @response.body

    get distillator_shadow_report_path, params: { status: "not_checked" }

    assert_response :success
    assert_match "Unknown queue", @response.body
    assert_match "Active queue", @response.body
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
      url: "https://promotable-queue.example/event",
      check_kind: "statement_delta",
      status: "checked",
      statement_count_delta_acceptable: true,
      checked_at: 1.hour.ago
    )
    ready.transition_evidences.create!(
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
    assert_match "Transition status", @response.body
    assert_match "Diagnostics", @response.body
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
    assert_match "Compare Condenser vs Wringer", @response.body
    assert_match "Open active cache", @response.body
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
      name: name,
      seedurl: seedurl,
      graph_name: "https://#{seedurl}.example/graph",
      default_language: "en",
      distillator_mode: mode
    )
  end

  def create_cache_for(website, url:, signals: { "transport_success" => true, "content_success" => true }, primary_issue_key: nil, primary_issue_label: nil, primary_issue_severity: nil, health_status: "healthy", health_severity: "ok", redirected: false, final_url: nil, html: "<html>cached</html>", body: "<html>cached</html>")
    website.webpages.create!(
      url: url,
      language: "en",
      rdf_uri: "adr:#{website.seedurl}",
      rdfs_class: rdfs_classes(:one)
    )

    Distillator::FetchCache.create!(
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
