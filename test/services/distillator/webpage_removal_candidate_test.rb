require "test_helper"

class Distillator::WebpageRemovalCandidateTest < ActiveSupport::TestCase
  setup do
    Distillator::FetchCache.delete_all
  end

  test "allows deletion when cache is a non retryable delete candidate with no newer success" do
    cache = Distillator::FetchCache.create!(
      uri_key: Distillator::WringerUrlKey.call("https://example.org/events").uri_key,
      normalized_url: "https://example.org/events",
      scrape_date: Time.zone.now,
      successful_refresh: 2.days.ago,
      http_response_code: 404,
      final_url: "https://example.org/events",
      signals: { "primary_issue_key" => "redirect_to_listing", "redirect_type" => "normal", "network_status" => "ok" },
      hints: ["redirect_to_listing"],
      primary_issue_key: "redirect_to_listing",
      delete_candidate: true
    )

    result = Distillator::WebpageRemovalCandidate.call("https://example.org/events")

    assert_equal cache, result.cache
    assert_equal true, result.delete?
    assert_equal :delete_candidate, result.reason
  end

  test "does not delete retryable anti bot issues" do
    Distillator::FetchCache.create!(
      uri_key: Distillator::WringerUrlKey.call("https://example.org/events").uri_key,
      normalized_url: "https://example.org/events",
      scrape_date: Time.zone.now,
      successful_refresh: 2.days.ago,
      http_response_code: 200,
      signals: { "primary_issue_key" => "queue_it" },
      hints: ["queue_it"],
      primary_issue_key: "queue_it",
      delete_candidate: false
    )

    result = Distillator::WebpageRemovalCandidate.call("https://example.org/events")

    assert_equal false, result.delete?
    assert_equal :not_delete_candidate, result.reason
  end

  test "does not delete when a newer successful refresh exists after the failed scrape" do
    Distillator::FetchCache.create!(
      uri_key: Distillator::WringerUrlKey.call("https://example.org/events").uri_key,
      normalized_url: "https://example.org/events",
      scrape_date: 2.days.ago,
      successful_refresh: 1.day.ago,
      http_response_code: 404,
      final_url: "https://example.org/events",
      signals: { "primary_issue_key" => "redirect_to_listing", "redirect_type" => "normal", "network_status" => "ok" },
      hints: ["redirect_to_listing"],
      primary_issue_key: "redirect_to_listing",
      delete_candidate: true
    )

    result = Distillator::WebpageRemovalCandidate.call("https://example.org/events")

    assert_not result.delete?
    assert_equal :newer_successful_refresh, result.reason
  end

  test "does not delete when cache delete candidate is stale but yaml policy no longer allows delete" do
    cache = Distillator::FetchCache.create!(
      uri_key: Distillator::WringerUrlKey.call("https://example.org/events").uri_key,
      normalized_url: "https://example.org/events",
      scrape_date: Time.zone.now,
      successful_refresh: 2.days.ago,
      primary_issue_key: "queue_it",
      delete_candidate: true,
      signals: { "primary_issue_key" => "queue_it" },
      hints: ["queue_it"]
    )

    result = Distillator::WebpageRemovalCandidate.call("https://example.org/events")

    assert_not result.delete?
    assert_equal :not_delete_candidate, result.reason
  end

  test "does not delete when successful refresh is at same time as scrape date" do
    timestamp = Time.zone.now
    source_url = "https://example.org/source-page"

    cache = Distillator::FetchCache.create!(
      uri_key: Distillator::WringerUrlKey.call(source_url).uri_key,
      normalized_url: source_url,
      scrape_date: timestamp,
      successful_refresh: timestamp,
      http_response_code: 200,
      final_url: "https://example.org/events",
      redirect_chain: [source_url, "https://example.org/events"],
      signals: {
        "primary_issue_key" => "redirect_to_listing",
        "primary_issue_delete" => true,
        "redirect_type" => "normal",
        "network_status" => "ok"
      },
      hints: ["redirect_to_listing"],
      primary_issue_key: "redirect_to_listing",
      delete_candidate: true
    )

    cache.reload
    assert_equal true, cache.delete_candidate
    assert_equal "redirect_to_listing", cache.primary_issue_key

    result = Distillator::WebpageRemovalCandidate.call(source_url)

    assert_equal false, result.delete?
    assert_equal :newer_successful_refresh, result.reason
  end

  test "uses primary issue key from signals when materialized column is missing" do
    source_url = "https://example.org/source-page"

    cache = Distillator::FetchCache.create!(
      uri_key: Distillator::WringerUrlKey.call(source_url).uri_key,
      normalized_url: source_url,
      scrape_date: Time.zone.now,
      successful_refresh: 2.days.ago,
      http_response_code: 200,
      final_url: "https://example.org/events",
      redirect_chain: [source_url, "https://example.org/events"],
      signals: {
        "primary_issue_key" => "redirect_to_listing",
        "primary_issue_delete" => true,
        "redirect_type" => "normal",
        "network_status" => "ok"
      },
      hints: ["redirect_to_listing"],
      delete_candidate: true
    )

    cache.update_column(:primary_issue_key, nil)

    result = Distillator::WebpageRemovalCandidate.call(source_url)

    assert_equal true, result.delete?
    assert_equal :delete_candidate, result.reason
  end

end
