require "test_helper"

class Distillator::TransitionCheckRunnerTest < ActiveSupport::TestCase
  test "creates or updates all three check kinds without changing rollout mode" do
    website = build_website
    cache = create_cache(website, signals: { "transport_success" => true, "content_success" => true, "statement_count_delta_acceptable" => true, "export_diff_checked" => true })

    result = Distillator::TransitionCheckRunner.call(website: website)

    assert_equal "shadow", website.reload.distillator_mode
    assert_equal %w[export_diff fetch_parity statement_delta], result.records.keys.map(&:to_s).sort
    assert_equal %w[export_diff fetch_parity statement_delta], website.transition_evidences.order(:check_kind).pluck(:check_kind)
    assert_equal "checked", result.records[:fetch_parity].status
    assert_equal "checked", result.records[:statement_delta].status
    assert_equal "checked", result.records[:export_diff].status
    assert_equal cache.normalized_url, result.records[:fetch_parity].url

    assert_no_difference("Distillator::TransitionEvidence.count") do
      Distillator::TransitionCheckRunner.call(website: website)
    end
  end

  test "failed fetch records failed fetch check" do
    website = build_website
    create_cache(website, signals: { "transport_success" => false, "content_success" => false }, health_status: "attempt_failed")

    result = Distillator::TransitionCheckRunner.call(website: website)

    assert_equal "failed", result.records[:fetch_parity].status
  end

  test "statement and export checks record pending when not implemented in cache signals" do
    website = build_website
    create_cache(website, signals: { "transport_success" => true, "content_success" => true })

    result = Distillator::TransitionCheckRunner.call(website: website)

    assert_equal "pending", result.records[:statement_delta].status
    assert_equal "pending", result.records[:export_diff].status
  end

  private

  def build_website
    Website.create!(
      name: "Runner site",
      seedurl: "runner-site",
      graph_name: "https://example.org/runner-site",
      default_language: "en",
      distillator_mode: "shadow"
    )
  end

  def create_cache(website, signals:, health_status: "healthy")
    url = "https://runner-site.example/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:runner-site", rdfs_class: rdfs_classes(:one))
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
