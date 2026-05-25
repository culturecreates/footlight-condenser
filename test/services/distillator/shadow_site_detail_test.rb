require "test_helper"

class Distillator::ShadowSiteDetailTest < ActiveSupport::TestCase
  test "builds read only detail sections without fetching" do
    website = Website.create!(
      name: "Hector Charland",
      seedurl: "hector-charland-com",
      graph_name: "https://example.org/hector-charland",
      default_language: "en",
      distillator_mode: "shadow"
    )
    url = "https://example.org/hector-charland/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:hector", rdfs_class: rdfs_classes(:one))
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

    detail = Distillator::ShadowSiteDetail.call(website: website)

    assert_equal website, detail.summary.website
    assert_includes detail.rollout_notes.join(" "), "La Vitrine pipeline"
  end

  test "root cause prioritizes statement failures over secondary legacy lookup issues" do
    website = Website.create!(
      name: "Statement priority",
      seedurl: "statement-priority",
      graph_name: "https://example.org/statement-priority",
      default_language: "en",
      distillator_mode: "shadow"
    )
    url = "https://example.org/statement-priority/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:statement-priority", rdfs_class: rdfs_classes(:one))
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
      check_kind: "fetch_parity",
      status: "checked",
      checked_at: 1.hour.ago,
      details: {
        reason: "legacy_lookup_missing_config",
        representative_webpages: [url],
        representative_webpage_count: 1,
        representative_url_results: [
          { url: url, fetch_status: "passed", fetch_reason: "ok", legacy_lookup_status: "missing_config", comparison_status: "review" }
        ]
      }
    )
    website.transition_evidences.create!(
      url: url,
      check_kind: "statement_delta",
      status: "failed",
      statement_count_delta_acceptable: false,
      checked_at: 1.hour.ago,
      details: {
        reason: "statement_refresh_failed",
        representative_webpages: [url],
        representative_webpage_count: 1,
        statements_failed_count: 1,
        failing_statements: [{ id: 42, source: "json_url / en", webpage_url: url }],
        refresh_errors: ["invalid url in json_url"]
      }
    )

    detail = Distillator::ShadowSiteDetail.call(website: website)

    assert_equal "statements", detail.root_cause[:failed_layer]
    assert_equal "Statement refresh failed for 1 statement.", detail.root_cause[:concrete_reason]
    assert_equal "Invalid URL from json_url", detail.statement_failure_groups.first[:reason]
    assert_equal "json_url / en", detail.statement_failure_groups.first[:source]
  end
end
