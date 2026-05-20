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
end
