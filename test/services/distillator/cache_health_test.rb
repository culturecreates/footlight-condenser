require "test_helper"

class Distillator::CacheHealthTest < ActiveSupport::TestCase
  CacheStub = Struct.new(
    :normalized_url,
    :final_url,
    :html,
    :successful_refresh,
    :scrape_date,
    :http_response_code,
    :signals,
    :hints,
    keyword_init: true
  )

  test "classifies blocked cache from network_status signal" do
    result = Distillator::CacheHealth.call(build_cache(signals: { "network_status" => "blocked" }, hints: []))

    assert_equal :blocked, result.status
    assert_equal ["blocked"], result.reasons
  end

  test "classifies failed network cache" do
    result = Distillator::CacheHealth.call(build_cache(signals: { "network_status" => "failed" }))

    assert_equal :network_failed, result.status
    assert_equal ["network_failed"], result.reasons
  end

  test "classifies never fetched cache" do
    result = Distillator::CacheHealth.call(build_cache(successful_refresh: nil, scrape_date: nil, http_response_code: nil, html: nil))

    assert_equal :never_fetched, result.status
    assert_equal ["never_fetched"], result.reasons
  end

  test "classifies attempted but failed cache without successful refresh" do
    result = Distillator::CacheHealth.call(
      build_cache(
        successful_refresh: nil,
        scrape_date: 10.minutes.ago,
        http_response_code: 200,
        html: nil,
        signals: {
          "network_status" => "ok",
          "content_type" => "html",
          "primary_issue_key" => "redirect_to_listing",
          "primary_issue_severity" => "failed",
          "content_success" => false
        },
        hints: ["redirect_to_listing"]
      )
    )

    assert_equal :attempt_failed, result.status
    assert_equal ["redirect_to_listing"], result.reasons
  end

  test "classifies empty body cache" do
    result = Distillator::CacheHealth.call(build_cache(hints: ["empty_body"], html: ""))

    assert_equal :empty_body, result.status
    assert_equal ["empty_body"], result.reasons
  end

  test "classifies preserved html after 404 failure" do
    result = Distillator::CacheHealth.call(build_cache(http_response_code: 404, scrape_date: Time.current, successful_refresh: 1.day.ago))

    assert_equal :preserved_after_failure, result.status
    assert_equal ["non_2xx_preserved_html"], result.reasons
  end

  test "classifies preserved html after 500 failure" do
    result = Distillator::CacheHealth.call(build_cache(http_response_code: 500, scrape_date: Time.current, successful_refresh: 1.day.ago))

    assert_equal :preserved_after_failure, result.status
    assert_equal ["non_2xx_preserved_html"], result.reasons
  end

  test "classifies redirect changed cache" do
    result = Distillator::CacheHealth.call(build_cache(final_url: "https://other.example.org/final"))

    assert_equal :redirect_changed, result.status
    assert_equal ["redirect_changed"], result.reasons
  end

  test "classifies stale cache" do
    result = Distillator::CacheHealth.call(build_cache(scrape_date: 8.days.ago))

    assert_equal :stale, result.status
    assert_equal ["stale"], result.reasons
  end

  test "classifies healthy cache" do
    result = Distillator::CacheHealth.call(build_cache)

    assert_equal :healthy, result.status
    assert_equal ["successful_2xx_refresh"], result.reasons
  end

  test "classifies unknown cache" do
    result = Distillator::CacheHealth.call(build_cache(http_response_code: nil, html: nil, successful_refresh: 1.day.ago, scrape_date: nil, signals: {}, hints: []))

    assert_equal :unknown, result.status
    assert_equal ["unknown"], result.reasons
  end

  private

  def build_cache(
    normalized_url: "http://example.org/page",
    final_url: "http://example.org/page",
    html: "<html>cached</html>",
    successful_refresh: 1.day.ago,
    scrape_date: 1.day.ago,
    http_response_code: 200,
    signals: { "network_status" => "ok", "content_type" => "html" },
    hints: []
  )
    CacheStub.new(
      normalized_url: normalized_url,
      final_url: final_url,
      html: html,
      successful_refresh: successful_refresh,
      scrape_date: scrape_date,
      http_response_code: http_response_code,
      signals: signals,
      hints: hints
    )
  end
end
