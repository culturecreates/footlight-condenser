require "test_helper"

class Distillator::ShadowSiteSummaryTest < ActiveSupport::TestCase
  test "unknown when no distillator cache evidence exists" do
    website = create_shadow_website(name: "Unknown shadow", seedurl: "unknown-shadow")

    summary = Distillator::ShadowSiteSummary.call(website: website, cache: nil)

    assert_equal :not_checked, summary.status
    assert_equal :wringer, summary.production_backend
    assert_equal :condenser, summary.testing_backend
    assert_equal :missing, summary.fetch_status
    assert_equal "Shadow", summary.mode_label
    assert_equal "Wringer", summary.production_backend_label
    assert_equal "Not checked", summary.readiness_label
    assert_equal "unknown", summary.severity
    assert_equal "Run transition check.", summary.primary_action
  end

  test "blocked when latest attempt failed and last good content was preserved" do
    website, cache = create_shadow_website_with_cache(
      name: "Blocked shadow",
      seedurl: "blocked-shadow",
      url: "https://blocked-shadow.example/event",
      health_status: "preserved_after_failure",
      health_severity: "medium",
      successful_refresh: 2.days.ago,
      scrape_date: 1.hour.ago,
      primary_issue_key: "redirect_to_listing",
      primary_issue_label: "Redirect to listing",
      primary_issue_severity: "failed",
      signals: {
        "transport_success" => true,
        "content_success" => false,
        "last_good_preserved_failure" => true
      }
    )

    summary = Distillator::ShadowSiteSummary.call(website: website, cache: cache)

    assert_equal :blocked, summary.status
    assert_equal :failed, summary.fetch_status
    assert_includes summary.blockers, "Cannot activate yet: fetch check failed."
    assert_equal "Blocked", summary.readiness_label
    assert_equal "high", summary.severity
    assert_equal "Cannot activate yet: fetch check failed.", summary.primary_blocker
  end

  test "review when evidence is incomplete and redirect changed" do
    website, cache = create_shadow_website_with_cache(
      name: "Review shadow",
      seedurl: "review-shadow",
      url: "https://review-shadow.example/event",
      health_status: "redirect_changed",
      health_severity: "low",
      successful_refresh: 10.days.ago,
      scrape_date: Time.zone.now,
      primary_issue_key: "queue_it",
      primary_issue_label: "Queue-it waiting room",
      primary_issue_severity: "warning",
      final_url: "https://other.example/event",
      redirected: true,
      signals: {
        "transport_success" => true
      }
    )

    summary = Distillator::ShadowSiteSummary.call(website: website, cache: cache)

    assert_equal :review, summary.status
    assert_equal :stale, summary.fetch_status
    assert_includes summary.warnings, "Needs review: fetch result redirected."
    assert_equal "Needs review", summary.readiness_label
    assert_equal "medium", summary.severity
    assert_equal "Needs review: fetch check is stale.", summary.primary_blocker
  end

  test "ready when evidence exists and no blockers or warnings remain" do
    website, cache = create_shadow_website_with_cache(
      name: "Ready shadow",
      seedurl: "ready-shadow",
      url: "https://ready-shadow.example/event",
      health_status: "healthy",
      health_severity: "ok",
      successful_refresh: 2.hours.ago,
      scrape_date: 1.hour.ago,
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "export_diff_checked" => true
      }
    )

    summary = Distillator::ShadowSiteSummary.call(website: website, cache: cache)

    assert_equal :review, summary.status
    assert_equal [], summary.blockers
    assert_includes summary.warnings, "Needs review: statements check is missing."
    assert_equal :wringer, summary.production_backend
    assert_equal :condenser, summary.testing_backend
    assert_equal "Needs review", summary.readiness_label
    assert_equal "medium", summary.severity
    assert_equal "Needs review: statements check is missing.", summary.primary_blocker
  end

  test "la vitrine site with missing export evidence is blocked instead of ready" do
    website, cache = create_shadow_website_with_cache(
      name: "Hector Charland",
      seedurl: "hector-charland-com",
      url: "https://hector-charland-com.example/event",
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "representative_urls_checked" => true,
        "statement_count_delta_acceptable" => true
      }
    )

    summary = Distillator::ShadowSiteSummary.call(website: website, cache: cache)

    assert_equal "lavitrine_pipeline", summary.cohort_key
    assert_equal :blocked, summary.status
    assert_includes summary.blockers, "Cannot activate yet: export check is missing."
    assert_equal "Cannot activate yet: statements check is missing.", summary.primary_blocker
  end

  test "non cohort site with missing export evidence is review" do
    website, cache = create_shadow_website_with_cache(
      name: "Outside Feed",
      seedurl: "outside-feed",
      url: "https://outside-feed.example/event",
      signals: {
        "transport_success" => true,
        "content_success" => true
      }
    )

    summary = Distillator::ShadowSiteSummary.call(website: website, cache: cache)

    assert_nil summary.cohort_key
    assert_equal :review, summary.status
    assert_includes summary.warnings, "Needs review: export check is missing."
    assert_equal "Needs review: statements check is missing.", summary.primary_blocker
  end

  test "la vitrine site with all stricter checks passes as ready" do
    website, cache = create_shadow_website_with_cache(
      name: "Hector Charland",
      seedurl: "hector-charland-com",
      url: "https://hector-charland-com.example/event",
      signals: {
        "transport_success" => true,
        "content_success" => true
      }
    )
    create_transition_evidence(website, "fetch_parity", details: { representative_urls_checked: true })
    create_transition_evidence(website, "statement_delta", statement_count_delta_acceptable: true)
    create_transition_evidence(website, "export_diff", export_diff_checked: true)

    summary = Distillator::ShadowSiteSummary.call(website: website, cache: cache)

    assert_equal :ready, summary.status
    assert_equal [], summary.blockers
    assert_equal [], summary.warnings
    assert_equal "Ready", summary.readiness_label
    assert_equal "ok", summary.severity
    assert_nil summary.primary_blocker
    assert_equal "Promote to Active.", summary.primary_action
  end

  test "latest fetch evidence failure overrides older healthy cache in the summary" do
    website, cache = create_shadow_website_with_cache(
      name: "Latest failed attempt",
      seedurl: "latest-failed-attempt",
      url: "https://latest-failed-attempt.example/event",
      signals: {
        "transport_success" => true,
        "content_success" => true
      }
    )
    create_transition_evidence(
      website,
      "fetch_parity",
      status: "failed",
      details: {
        attempted_condenser_fetch: true,
        comparison_performed: false,
        representative_urls_checked: true,
        reason: "empty_body"
      }
    )

    summary = Distillator::ShadowSiteSummary.call(website: website, cache: cache)

    assert_equal :blocked, summary.status
    assert_equal :failed, summary.fetch_status
    assert_includes summary.blockers, "Cannot activate yet: fetch check failed."
  end

  test "non cohort site with stale durable evidence is review" do
    website, cache = create_shadow_website_with_cache(
      name: "Outside Feed",
      seedurl: "outside-feed",
      url: "https://outside-feed.example/event",
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "export_diff_checked" => true
      }
    )
    create_transition_evidence(website, "export_diff", export_diff_checked: true, checked_at: 4.days.ago)

    summary = Distillator::ShadowSiteSummary.call(website: website, cache: cache)

    assert_equal :review, summary.status
    assert_includes summary.warnings, "Needs review: export check is stale."
  end

  private

  def create_shadow_website(name:, seedurl:)
    Website.create!(
      name: name,
      seedurl: seedurl,
      graph_name: "https://#{seedurl}.example/graph",
      default_language: "en",
      distillator_mode: "shadow"
    )
  end

  def create_shadow_website_with_cache(name:, seedurl:, url:, **cache_attrs)
    website = create_shadow_website(name: name, seedurl: seedurl)
    website.webpages.create!(
      url: url,
      language: "en",
      rdf_uri: "adr:#{seedurl}",
      rdfs_class: rdfs_classes(:one)
    )

    cache = Distillator::FetchCache.create!(
      {
        uri_key: CGI.escape(url),
        normalized_url: url,
        name: name,
        html: cache_attrs.fetch(:html, "<html>cached</html>"),
        body: cache_attrs.fetch(:body, "<html>cached</html>"),
        http_response_code: 200,
        scrape_date: Time.zone.now,
        successful_refresh: Time.zone.now,
        headers: {},
        signals: { "transport_success" => true, "content_success" => true },
        hints: Array(cache_attrs[:primary_issue_key]).compact,
        final_url: url,
        redirect_chain: [],
        health_status: "healthy",
        health_severity: "ok"
      }.merge(cache_attrs).tap do |attrs|
        attrs[:signals] = attrs.fetch(:signals, {}).merge(
          "primary_issue_key" => attrs[:primary_issue_key],
          "primary_issue_label" => attrs[:primary_issue_label],
          "primary_issue_severity" => attrs[:primary_issue_severity]
        ).compact
      end
    )

    [website, cache]
  end

  def create_transition_evidence(website, check_kind, checked_at: 1.hour.ago, status: "checked", **attrs)
    website.transition_evidences.create!(
      {
        url: "https://evidence.example/#{website.seedurl}/#{check_kind}",
        check_kind: check_kind,
        status: status,
        checked_at: checked_at
      }.merge(attrs)
    )
  end
end
