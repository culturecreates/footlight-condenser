require "test_helper"

class WebsitesHelperTest < ActionView::TestCase
  test "legacy contract exposes move to shadow only" do
    website = build_website("legacy", seedurl: "helper-legacy")
    Distillator::TransitionRuntime.stubs(:allow_active_override?).returns(false)

    contract = website_transition_contract(website)

    assert_equal "legacy", contract[:current_mode]
    assert_equal "Move to shadow", contract[:next_action_label]
    assert_equal "shadow", contract[:next_mode]
    assert_equal true, contract[:action_enabled]
    assert_equal false, contract[:override_allowed]
    assert_equal false, contract[:rollback_available]
  end

  test "shadow ready contract exposes promote to active" do
    website = ready_shadow_website(seedurl: "helper-shadow-ready")

    contract = website_transition_contract(website)

    assert_equal "shadow", contract[:current_mode]
    assert_equal "Promote to active", contract[:next_action_label]
    assert_equal "active", contract[:next_mode]
    assert_equal true, contract[:action_enabled]
    assert_equal [], contract[:blockers]
  end

  test "shadow blocked contract exposes disabled promotion and blockers" do
    website = blocked_shadow_website(seedurl: "helper-shadow-blocked")

    contract = website_transition_contract(website)

    assert_equal "shadow", contract[:current_mode]
    assert_equal "Cannot promote yet", contract[:next_action_label]
    assert_equal "active", contract[:next_mode]
    assert_equal false, contract[:action_enabled]
    assert_includes contract[:blockers], "Cannot activate yet: statements check failed."
  end

  test "shadow review contract exposes activate after review instead of promote or activate anyway" do
    website = build_website("shadow", seedurl: "helper-shadow-review")
    url = "https://example.org/helper-shadow-review/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:helper-shadow-review", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: url
    )
    website.transition_evidences.create!(url: url, check_kind: "statement_delta", status: "checked", statement_count_delta_acceptable: true, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: url, check_kind: "export_diff", status: "checked", export_diff_checked: true, checked_at: 1.hour.ago)
    website.transition_evidences.create!(
      url: url,
      check_kind: "fetch_parity",
      status: "checked",
      checked_at: 1.hour.ago,
      details: { reason: "review_needed_difference", comparison_policy: "operator", compare_summary: { review_needed_diffs: %w[html_sha256] } }
    )

    contract = website_transition_contract(website)

    assert_equal "Review before activating", contract[:next_action_label]
    assert_equal false, contract[:action_enabled]
    assert_empty contract[:secondary_actions].select { |action| action[:kind] == :button }
    assert_equal ["Activate after review"], contract[:secondary_actions].select { |action| action[:kind] == :override }.map { |action| action[:label] }
  end

  test "shadow body omitted contract does not expose activate after review" do
    website = build_website("shadow", seedurl: "helper-shadow-body-omitted")
    url = "https://example.org/helper-shadow-body-omitted/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:helper-shadow-body-omitted", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: url
    )
    website.transition_evidences.create!(url: url, check_kind: "statement_delta", status: "checked", statement_count_delta_acceptable: true, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: url, check_kind: "export_diff", status: "checked", export_diff_checked: true, checked_at: 1.hour.ago)
    website.transition_evidences.create!(
      url: url,
      check_kind: "fetch_parity",
      status: "checked",
      checked_at: 1.hour.ago,
      details: { reason: "legacy_lookup_body_omitted", comparison_policy: "operator" }
    )

    contract = website_transition_contract(website)

    assert_equal "Cannot promote yet", contract[:next_action_label]
    assert_empty contract[:secondary_actions].select { |action| action[:kind] == :override && action[:label] == "Activate after review" }
  end

  test "active contract exposes rollback" do
    website = build_website("active", seedurl: "helper-active")

    contract = website_transition_contract(website)

    assert_equal "active", contract[:current_mode]
    assert_equal "Rollback to Legacy Wringer", contract[:next_action_label]
    assert_equal "legacy", contract[:next_mode]
    assert_equal true, contract[:action_enabled]
    assert_equal true, contract[:rollback_available]
  end

  test "website webpage summary cell links to scoped webpages filters" do
    website = build_website("legacy", seedurl: "summary-cell")
    summary = {
      total: 7,
      public_urls: 4,
      internal_uris: 3,
      by_class: {
        "Event" => 2,
        "Person" => 1,
        "Place" => 1,
        "ResourceList" => 1,
        "WebPage" => 1,
        "Other" => 1
      },
      publishable: 1,
      not_publishable: 6
    }

    html = website_webpage_summary_cell(website, summary)

    assert_includes html, "/webpages?seedurl=summary-cell"
    assert_includes html, "/webpages?seedurl=summary-cell&amp;url_kind=public"
    assert_includes html, "/webpages?rdfs_class=Event&amp;seedurl=summary-cell"
    assert_match %r{/webpages\?(publishable=true&amp;seedurl=summary-cell|seedurl=summary-cell&amp;publishable=true)}, html
    assert_includes html, "E2"
    assert_includes html, "6 not publishable"
  end

  test "transition status summary reports readiness and check states" do
    website = ready_shadow_website(seedurl: "summary-transition-ready")

    summary = website_transition_status_summary(website)

    assert_includes summary, "Ready"
    assert_includes summary, "fetch passed"
    assert_includes summary, "statements passed"
    assert_includes summary, "export passed"
  end

  test "transition verdict line renders compact blocker text once" do
    website = blocked_shadow_website(seedurl: "summary-transition-blocked-verdict")

    assert_equal "Blocked: statements check failed.", website_transition_verdict_line(website)
  end

  test "transition secondary status line uses statements export fetch order" do
    website = ready_shadow_website(seedurl: "summary-transition-secondary-order")

    assert_equal "Statements passed | Export passed | Fetch passed", website_transition_secondary_status_line(website)
  end

  test "transition evidence summary mentions recorded evidence and report path" do
    website = ready_shadow_website(seedurl: "summary-transition-evidence")

    summary = website_transition_evidence_summary(website)
    path = website_transition_report_path(website)

    assert_includes summary, "Fetch parity checked"
    assert_includes summary, "Statement coverage checked."
    assert_includes summary, "Export comparison checked."
    assert_equal distillator_shadow_report_site_path(website, anchor: "transition-report-summary"), path
  end

  test "transition evidence freshness text shows latest timestamp when evidence exists" do
    website = ready_shadow_website(seedurl: "summary-transition-freshness")

    text = website_transition_evidence_freshness_text(website)

    assert_includes text, "Latest transition evidence:"
    refute_includes text, "Waiting for new transition evidence"
  end

  test "transition evidence freshness text shows not recorded when no evidence exists" do
    website = build_website("shadow", seedurl: "summary-transition-no-evidence")

    assert_equal "Latest transition evidence: Not recorded yet.", website_transition_evidence_freshness_text(website)
  end

  test "transition evidence freshness text prefers pending message over stale timestamp" do
    website = ready_shadow_website(seedurl: "summary-transition-pending")
    website.update!(transition_check_requested_at: 5.minutes.ago)
    website.transition_evidences.update_all(checked_at: 10.minutes.ago)

    assert_equal "Batch check requested. Waiting for new transition evidence.", website_transition_evidence_freshness_text(website.reload)
  end

  test "transition drill down links render report cache and webpage targets once" do
    website = ready_shadow_website(seedurl: "summary-transition-drilldown")

    links = website_transition_drill_down_links(website)

    assert_equal 3, links.length
    assert_includes links.first, "Latest transition report"
    assert_includes links.second, "Open cache diagnostics"
    assert_includes links.third, "Inspect publishable event pages"
  end

  test "website transition secondary actions do not expose run transition check labels" do
    website = ready_shadow_website(seedurl: "summary-transition-secondary-actions")

    contract = website_transition_contract(website)

    refute_includes contract[:secondary_actions].map { |action| action[:label] }, "Run transition check"
    refute_includes contract[:secondary_actions].map { |action| action[:label] }, "Run transition check again"
  end

  private

  def build_website(mode, seedurl:)
    Website.create!(
      name: "Helper website #{seedurl}",
      seedurl: seedurl,
      graph_name: "https://example.org/#{seedurl}",
      default_language: "en",
      distillator_mode: mode
    )
  end

  def ready_shadow_website(seedurl:)
    website = build_website("shadow", seedurl: seedurl)
    url = "https://example.org/#{seedurl}/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:#{seedurl}", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: url
    )
    website.transition_evidences.create!(url: url, check_kind: "fetch_parity", status: "checked", details: { representative_urls_checked: true }, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: url, check_kind: "statement_delta", status: "checked", statement_count_delta_acceptable: true, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: url, check_kind: "export_diff", status: "checked", export_diff_checked: true, checked_at: 1.hour.ago)
    website
  end

  def blocked_shadow_website(seedurl:)
    website = build_website("shadow", seedurl: seedurl)
    url = "https://example.org/#{seedurl}/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:#{seedurl}", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: url
    )
    website.transition_evidences.create!(
      url: url,
      check_kind: "statement_delta",
      status: "failed",
      statement_count_delta_acceptable: false,
      checked_at: 1.hour.ago
    )
    website
  end
end
