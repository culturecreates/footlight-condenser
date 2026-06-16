require "test_helper"

class HarmonizedCardPartialsTest < ActionDispatch::IntegrationTest
  setup do
    Distillator::FetchCache.delete_all
  end

  test "cache index renders harmonized summary card hooks" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get distillator_cache_index_path(term: cache.normalized_url)

    assert_response :success
    assert_select ".harmonized-card-grid", minimum: 1
    assert_select ".harmonized-card", minimum: 1
    assert_select ".harmonized-card-title", minimum: 1
    assert_select ".harmonized-card-value", minimum: 1
    assert_select ".harmonized-card-status", minimum: 1
  end

  test "cache show renders harmonized record card hooks" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get distillator_cache_path(cache)

    assert_response :success
    assert_select ".harmonized-card-grid", minimum: 1
    assert_select ".harmonized-card", minimum: 1
    assert_select ".harmonized-card-title", minimum: 1
    assert_select ".harmonized-card-value", minimum: 1
    assert_select ".harmonized-card-status", minimum: 1
    assert_select ".harmonized-card-actions", minimum: 1
  end

  private

  def create_cache
    Distillator::FetchCache.create!(
      uri_key: CGI.escape("http://example.org/cached"),
      normalized_url: "http://example.org/cached",
      html: "<html>cached</html>",
      body: "<html>cached</html>",
      name: "Cached",
      scrape_date: Time.zone.now,
      successful_refresh: Time.zone.now,
      http_response_code: 200,
      headers: {},
      signals: { "network_status" => "ok", "transport_success" => true, "content_success" => true, "content_type" => "html" },
      hints: [],
      redirect_chain: []
    )
  end
end
