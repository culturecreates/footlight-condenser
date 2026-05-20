require "test_helper"

class Distillator::TransitionCheckTest < ActiveSupport::TestCase
  test "blocked cache health makes promotable false" do
    website = build_website("blocked-transition-check")
    cache = build_cache(
      website: website,
      url: "https://blocked-transition-check.example/event",
      signals: { "transport_success" => false, "content_success" => false },
      health_status: "attempt_failed"
    )

    result = Distillator::TransitionCheck.call(website: website, cache: cache)

    assert_equal website.id, result.website_id
    assert_equal :shadow, result.mode
    assert_equal false, result.promotable
    assert_equal :wringer, result.active_backend
    assert_equal cache.reload.health_status.to_s.presence || "unknown", result.latest_cache_status
    assert_equal true, result.cache_present
    assert result.blocking_issues.any?
  end

  test "healthy shadow cache with representative checks makes promotable true" do
    website = build_website("ready-transition-check")
    url = "https://ready-transition-check.example/event"
    cache = build_cache(
      website: website,
      url: url,
      signals: { "transport_success" => true, "content_success" => true }
    )
    website.transition_evidences.create!(url: url, check_kind: "statement_delta", status: "checked", statement_count_delta_acceptable: true, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: url, check_kind: "export_diff", status: "checked", export_diff_checked: true, checked_at: 1.hour.ago)

    result = Distillator::TransitionCheck.call(website: website, cache: cache)

    assert_equal :ready, result.status
    assert_equal true, result.promotable
    assert_equal :passed, result.fetch
    assert_equal :passed, result.statements
    assert_equal :passed, result.export
    assert_equal true, result.compare_available
  end

  private

  def build_website(seedurl)
    Website.create!(
      name: seedurl,
      seedurl: seedurl,
      graph_name: "https://example.org/#{seedurl}",
      default_language: "en",
      distillator_mode: "shadow"
    )
  end

  def build_cache(website:, url:, signals:, health_status: "healthy")
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:#{website.seedurl}", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: signals,
      final_url: url,
      health_status: health_status
    )
  end
end
