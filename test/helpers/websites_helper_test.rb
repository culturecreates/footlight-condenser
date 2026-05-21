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

  test "active contract exposes rollback" do
    website = build_website("active", seedurl: "helper-active")

    contract = website_transition_contract(website)

    assert_equal "active", contract[:current_mode]
    assert_equal "Rollback to Legacy Wringer", contract[:next_action_label]
    assert_equal "legacy", contract[:next_mode]
    assert_equal true, contract[:action_enabled]
    assert_equal true, contract[:rollback_available]
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
