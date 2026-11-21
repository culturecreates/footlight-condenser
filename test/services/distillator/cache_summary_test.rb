require "test_helper"

class Distillator::CacheSummaryTest < ActiveSupport::TestCase
  setup do
    Distillator::FetchCache.delete_all
  end

  test "counts cards correctly from a relation-backed scope" do
    create_cache(uri: "http://example.org/healthy", http_response_code: 200)
    create_cache(
      uri: "http://example.org/preserved",
      http_response_code: 404,
      scrape_date: Time.zone.now,
      successful_refresh: 2.days.ago,
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "content_success" => false,
        "primary_issue_key" => "http_4xx",
        "primary_issue_severity" => "failed",
        "last_good_preserved_failure" => true
      },
      hints: ["last_good_preserved_failure"]
    )
    create_cache(uri: "http://example.org/network", signals: { "network_status" => "failed", "content_type" => "html" })
    create_cache(uri: "http://example.org/blocked", signals: { "error_type" => "DistillatorFetchBlocked", "content_type" => "html" }, hints: ["blocked"])
    create_cache(uri: "http://example.org/missing-html", html: nil, body: nil, successful_refresh: nil)
    create_cache(uri: "http://example.org/redirect", final_url: "http://example.org/final", redirect_chain: ["http://example.org/redirect", "http://example.org/final"])
    create_cache(uri: "http://example.org/json", signals: { "network_status" => "ok", "content_type" => "json" })
    create_cache(
      uri: "http://example.org/server",
      http_response_code: 500,
      scrape_date: Time.zone.now,
      successful_refresh: 1.day.ago,
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "content_success" => false,
        "primary_issue_key" => "http_5xx",
        "primary_issue_severity" => "failed",
        "last_good_preserved_failure" => true
      },
      hints: ["last_good_preserved_failure"]
    )
    create_cache(
      uri: "http://example.org/empty",
      html: "<html></html>",
      body: "",
      signals: { "network_status" => "ok", "content_type" => "html", "empty_body" => true },
      hints: ["empty_body"],
      http_response_code: 200
    )
    create_cache(uri: "http://example.org/stale", scrape_date: 8.days.ago, successful_refresh: 8.days.ago)

    scope = Distillator::FetchCache.all
    scope.expects(:to_a).never
    cards = Distillator::CacheSummary.call(scope: scope)

    counts = cards.index_by { |card| card[:key] }.transform_values { |card| card[:count] }
    assert_equal 10, counts[:total]
    assert_equal 1, counts[:network_failed]
    assert_equal 1, counts[:blocked]
    assert_equal 1, counts[:missing_html]
    assert_equal 1, counts[:empty_body]
    assert_equal 1, counts[:status_4xx]
    assert_equal 1, counts[:status_5xx]
    assert_equal 1, counts[:redirected]
    assert_equal 1, counts[:json_detected]
    assert_equal 3, counts[:healthy]
    assert_equal 2, counts[:preserved_after_failure]
    assert_equal 1, counts[:stale]
  end

  private

  def create_cache(uri:, html: "<html>cached</html>", body: html, name: "Cached", signals: { "network_status" => "ok", "content_type" => "html" }, hints: [], final_url: nil, redirect_chain: [], http_response_code: 200, scrape_date: Time.zone.now, successful_refresh: Time.zone.now)
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(uri),
      normalized_url: uri,
      html: html,
      body: body,
      name: name,
      scrape_date: scrape_date,
      successful_refresh: successful_refresh,
      http_response_code: http_response_code,
      headers: {},
      signals: signals,
      hints: hints,
      final_url: final_url,
      redirect_chain: redirect_chain
    )
  end
end
