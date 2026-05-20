require "test_helper"

class Distillator::ShadowReportTest < ActiveSupport::TestCase
  test "report returns tracked websites across rollout modes and summarizes status counts" do
    baseline = Distillator::ShadowReport.call(filters: {}, sort: "website", direction: "asc", page: 1, per_page: 100)

    create_shadow_site(name: "Ready shadow", seedurl: "ready-shadow", status: :ready)
    create_shadow_site(name: "Blocked shadow", seedurl: "blocked-shadow", status: :blocked, issue_key: "timeout")
    create_shadow_site(name: "Hector Charland", seedurl: "hector-charland-com", status: :review, issue_key: "queue_it", lavitrine: true)
    create_website(name: "Legacy site", seedurl: "legacy-site", mode: "legacy")
    create_website(name: "Active site", seedurl: "active-site", mode: "active")

    report = Distillator::ShadowReport.call(filters: {}, sort: "website", direction: "asc", page: 1, per_page: 25)

    assert_includes report.rows.map { |row| row.website.name }, "Active site"
    assert_includes report.rows.map { |row| row.website.name }, "Blocked shadow"
    assert_includes report.rows.map { |row| row.website.name }, "Hector Charland"
    assert_includes report.rows.map { |row| row.website.name }, "Legacy site"
    assert_includes report.rows.map { |row| row.website.name }, "Ready shadow"
    assert_equal baseline.summary_counts[:total] + 5, report.summary_counts[:total]
    assert_equal baseline.summary_counts[:ready] + 1, report.summary_counts[:ready]
    assert_equal baseline.summary_counts[:review] + 1, report.summary_counts[:review]
    assert_equal baseline.summary_counts[:blocked] + 1, report.summary_counts[:blocked]
    assert_equal baseline.summary_counts[:not_checked] + 2, report.summary_counts[:not_checked]
    assert_equal baseline.summary_counts[:lavitrine_total] + 1, report.summary_counts[:lavitrine_total]
    assert_equal baseline.summary_counts[:lavitrine_review] + 1, report.summary_counts[:lavitrine_review]
    assert_equal baseline.dashboard_counts[:legacy_sites] + 1, report.dashboard_counts[:legacy_sites]
    assert_equal baseline.dashboard_counts[:shadow_sites] + 3, report.dashboard_counts[:shadow_sites]
    assert_equal baseline.dashboard_counts[:active_sites] + 1, report.dashboard_counts[:active_sites]
    assert_equal baseline.blocker_counts[:failed_fetch] + 1, report.blocker_counts[:failed_fetch]
    assert_equal baseline.blocker_counts[:missing_statement_evidence] + 3, report.blocker_counts[:missing_statement_evidence]
    assert_equal baseline.blocker_counts[:missing_export_evidence] + 3, report.blocker_counts[:missing_export_evidence]
    assert_equal baseline.blocker_counts[:redirect_cache_health_review] + 1, report.blocker_counts[:redirect_cache_health_review]
    assert report.rows.all? { |row| row.testing_backend == :condenser }
  end

  test "report supports cohort slicing" do
    create_shadow_site(name: "Hector Charland", seedurl: "hector-charland-com", status: :review, issue_key: "queue_it", lavitrine: true)
    create_shadow_site(name: "Other review", seedurl: "other-review", status: :review, issue_key: "queue_it")

    lavitrine = Distillator::ShadowReport.call(
      filters: { cohort: "lavitrine_pipeline" },
      sort: "website",
      direction: "asc",
      page: 1,
      per_page: 25
    )
    other = Distillator::ShadowReport.call(
      filters: { cohort: "other" },
      sort: "website",
      direction: "asc",
      page: 1,
      per_page: 25
    )

    assert_includes lavitrine.rows.map { |row| row.website.name }, "Hector Charland"
    refute_includes lavitrine.rows.map { |row| row.website.name }, "Other review"
    assert_includes other.rows.map { |row| row.website.name }, "Other review"
    refute_includes other.rows.map { |row| row.website.name }, "Hector Charland"
  end

  test "global counts remain visible when filters narrow the row set" do
    baseline = Distillator::ShadowReport.call(filters: {}, sort: "website", direction: "asc", page: 1, per_page: 100)

    create_shadow_site(name: "Ready shadow", seedurl: "ready-shadow", status: :ready)
    create_shadow_site(name: "Blocked shadow", seedurl: "blocked-shadow", status: :blocked, issue_key: "timeout")
    create_website(name: "Legacy site", seedurl: "legacy-site", mode: "legacy")

    report = Distillator::ShadowReport.call(
      filters: { status: "ready" },
      sort: "website",
      direction: "asc",
      page: 1,
      per_page: 25
    )

    assert_equal 1, report.summary_counts[:total]
    assert_equal baseline.global_summary_counts[:total] + 3, report.global_summary_counts[:total]
    assert_equal baseline.global_summary_counts[:blocked] + 1, report.global_summary_counts[:blocked]
  end

  test "report supports rollout mode slicing" do
    create_shadow_site(name: "Shadow site", seedurl: "shadow-site", status: :ready)
    create_website(name: "Legacy site", seedurl: "legacy-site", mode: "legacy")
    create_website(name: "Active site", seedurl: "active-site", mode: "active")

    active_report = Distillator::ShadowReport.call(
      filters: { mode: "active" },
      sort: "website",
      direction: "asc",
      page: 1,
      per_page: 25
    )

    assert_equal ["Active site"], active_report.rows.map { |row| row.website.name }
  end

  test "report supports promotable slicing" do
    create_shadow_site(name: "Promotable site", seedurl: "promotable-site", status: :ready)
    create_shadow_site(name: "Blocked site", seedurl: "blocked-site", status: :blocked, issue_key: "timeout")

    yes_report = Distillator::ShadowReport.call(
      filters: { promotable: "yes", term: "site" },
      sort: "website",
      direction: "asc",
      page: 1,
      per_page: 25
    )
    no_report = Distillator::ShadowReport.call(
      filters: { promotable: "no", term: "site" },
      sort: "website",
      direction: "asc",
      page: 1,
      per_page: 25
    )

    assert_equal ["Promotable site"], yes_report.rows.map { |row| row.website.name }
    assert_includes no_report.rows.map { |row| row.website.name }, "Blocked site"
    refute_includes no_report.rows.map { |row| row.website.name }, "Promotable site"
  end

  private

  def create_website(name:, seedurl:, mode:)
    Website.create!(
      name: name,
      seedurl: seedurl,
      graph_name: "https://#{seedurl}.example/graph",
      default_language: "en",
      distillator_mode: mode
    )
  end

  def create_shadow_site(name:, seedurl:, status:, issue_key: nil, lavitrine: false)
    website = create_website(name: name, seedurl: seedurl, mode: "shadow")
    url_seed = seedurl
    url = "https://#{url_seed}.example/event"
    website.webpages.create!(
      url: url,
      language: "en",
      rdf_uri: "adr:#{url_seed}",
      rdfs_class: rdfs_classes(:one)
    )

    attrs = {
      uri_key: CGI.escape(url),
      normalized_url: url,
      name: name,
      html: "<html>cached</html>",
      body: "<html>cached</html>",
      http_response_code: 200,
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true, "primary_issue_key" => issue_key }.compact,
      hints: Array(issue_key).compact,
      final_url: url,
      redirect_chain: [],
      health_status: "healthy",
      health_severity: "ok",
      primary_issue_key: issue_key,
      primary_issue_label: issue_key&.humanize
    }

    attrs[:signals] = attrs[:signals].merge("export_diff_checked" => true, "statement_count_delta_acceptable" => true) if status == :ready

    if status == :blocked
      attrs[:health_status] = "attempt_failed"
      attrs[:health_severity] = "high"
      attrs[:signals] = { "transport_success" => false, "content_success" => false, "primary_issue_key" => issue_key, "primary_issue_severity" => "failed" }.compact
      attrs[:primary_issue_severity] = "failed"
    elsif status == :review
      attrs[:health_status] = "redirect_changed"
      attrs[:health_severity] = "low"
      attrs[:signals] = { "transport_success" => true, "primary_issue_key" => issue_key, "primary_issue_severity" => "warning" }.compact
      attrs[:primary_issue_severity] = "warning"
      attrs[:redirected] = true
      attrs[:final_url] = "#{url}/redirected"
    end

    if lavitrine
      attrs[:signals] = attrs[:signals].merge("statement_count_delta_acceptable" => true, "export_diff_checked" => true)
    end

    Distillator::FetchCache.create!(attrs)
    if lavitrine
      website.transition_evidences.create!(
        url: url,
        check_kind: "statement_delta",
        status: "checked",
        statement_count_delta_acceptable: true,
        checked_at: 1.hour.ago
      )
      website.transition_evidences.create!(
        url: url,
        check_kind: "export_diff",
        status: "checked",
        export_diff_checked: true,
        checked_at: 1.hour.ago
      )
    end
    website
  end
end
