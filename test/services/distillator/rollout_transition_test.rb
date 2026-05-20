require "test_helper"

class Distillator::RolloutTransitionTest < ActiveSupport::TestCase
  test "blocks direct legacy to active by default" do
    website = build_website("legacy")

    result = Distillator::RolloutTransition.call(website: website, to_mode: "active", actor: "test")

    assert_equal false, result.success?
    assert_equal "legacy", website.reload.distillator_mode
    assert_includes result.errors, "Direct legacy to active promotion is blocked"
  end

  test "blocks shadow to active when status is review" do
    website = build_website("shadow")
    url = "https://example.org/review"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:review", rdfs_class: rdfs_classes(:one))
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

    result = Distillator::RolloutTransition.call(website: website, to_mode: "active", actor: "test")

    assert_equal false, result.success?
    assert_includes result.errors, "Cannot activate yet: statements check is missing."
  end

  test "allows shadow to active when status is ready" do
    website = build_website("shadow", seedurl: "hector-charland-com")
    url = "https://example.org/ready"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:ready", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true, "statement_count_delta_acceptable" => true, "export_diff_checked" => true },
      final_url: url
    )
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

    result = Distillator::RolloutTransition.call(website: website, to_mode: "active", actor: "test")

    assert_equal true, result.success?
    assert_equal "active", website.reload.distillator_mode
  end

  test "allows active rollback to legacy even when readiness would fail" do
    website = build_website("active", seedurl: "hector-charland-com")

    result = Distillator::RolloutTransition.call(website: website, to_mode: "legacy", actor: "test")

    assert_equal true, result.success?
    assert_equal "legacy", website.reload.distillator_mode
  end

  private

  def build_website(mode, seedurl: "rollout-transition")
    Website.create!(
      name: "Rollout transition #{mode}",
      seedurl: seedurl,
      graph_name: "https://example.org/#{seedurl}",
      default_language: "en",
      distillator_mode: mode
    )
  end
end
