require "test_helper"

class Distillator::CacheUiParityTest < ActionDispatch::IntegrationTest
  setup do
    Distillator::FetchCache.delete_all
    @old_refresh_ui = ENV["DISTILLATOR_CACHE_REFRESH_UI"]
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
  end

  teardown do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = @old_refresh_ui
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
  end

  test "cache refresh ui flag shows operational fetch parity matrix from the cache index" do
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"
    cache = create_cache(
      normalized_url: "https://example.org/event",
      html: "<html><title>Event</title><body>Hello world preview snippet</body></html>",
      http_response_code: 200
    )
    Distillator::FetchCacheStore.expects(:fetch).never

    get distillator_cache_index_path

    assert_response :success
    assert_match "Fetch URL", @response.body
    assert_match "Direct fetch", @response.body
    assert_match "Rendered fetch", @response.body
    assert_match "POST fetch", @response.body
    assert_match "Direct fetch = normal cached fetch", @response.body
    assert_match "Rendered fetch = JavaScript/rendered fetch with fragment support", @response.body
    assert_match "POST fetch = JSON POST source fetch", @response.body
    assert_match ".json", @response.body
    assert_match "Raw", @response.body
    assert_match "Show", @response.body
    assert_match "Hello world preview snippet", @response.body
    assert_match "Compatibility API", @response.body
    assert_match "Cached Wringer-compatible JSON", @response.body
    assert_match "Cache fetch actions", @response.body
    assert_match "/websites/wring.json?uri=URL", @response.body
    assert_match distillator_cache_path(cache), @response.body
    assert_match raw_distillator_cache_path(cache), @response.body
    assert_match wring_json_distillator_cache_path(cache), @response.body
    assert_match "Compare", @response.body
    assert_no_match "Distillator", visible_text(@response.body)
    assert_no_match "DISTILLATOR_CACHE_REFRESH_UI", visible_text(@response.body)
    assert_no_match "/distillator/cache", visible_text(@response.body)
    assert_no_match "Preview Direct fetch", visible_text(@response.body)
    assert_no_match "Preview Rendered fetch", visible_text(@response.body)
    assert_no_match "Preview POST", visible_text(@response.body)
    assert_no_match "Cache preview endpoint", visible_text(@response.body)
    assert_no_match "Read-only cache inspection only", visible_text(@response.body)
    assert_no_match "Refresh actions are disabled", visible_text(@response.body)
  end

  test "shadow mode keeps cache inspection fallback copy" do
    ENV["DISTILLATOR_FETCH_MODE"] = "shadow"
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = nil
    cache = create_cache(
      normalized_url: "https://example.org/event",
      html: "<html><title>Event</title><body>Hello world preview snippet</body></html>",
      http_response_code: 200
    )
    Distillator::FetchCacheStore.expects(:fetch).never

    get distillator_cache_index_path

    assert_response :success
    assert_match "Cache inspection mode. Refresh actions are not available in this environment.", @response.body
    assert_match "Show", @response.body
    assert_match "Raw", @response.body
    assert_match ".json", @response.body
    assert_match "Pretty JSON", @response.body
    assert_match "Compare", @response.body
    assert_no_match %r{button[^>]*>Direct fetch</button>}, @response.body
    assert_no_match %r{button[^>]*>Rendered fetch</button>}, @response.body
    assert_no_match %r{button[^>]*>POST fetch</button>}, @response.body
    assert_match distillator_cache_path(cache), @response.body
    assert_no_match "Distillator", visible_text(@response.body)
    assert_no_match "DISTILLATOR_CACHE_REFRESH_UI", visible_text(@response.body)
    assert_no_match "/distillator/cache", visible_text(@response.body)
    assert_no_match "Preview Direct fetch", visible_text(@response.body)
  end

  test "parity view shows semantic content failure warning alongside transport success" do
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    create_cache(
      normalized_url: "https://www.ovation.ca/event",
      html: "<html>last good</html>",
      http_response_code: 200
    ).update!(
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "transport_success" => true,
        "content_success" => false,
        "primary_issue_key" => "redirect_to_listing",
        "primary_issue_label" => "Redirect to listing",
        "last_good_preserved_failure" => true
      },
      hints: ["redirect_to_listing", "last_good_preserved_failure"]
    )
    Distillator::FetchCacheStore.expects(:fetch).never

    get distillator_cache_index_path, params: { view: "parity" }

    assert_response :success
    text = visible_text(@response.body)
    assert_match "HTTP 200 but content failed: Redirect to listing", text
    assert_match "Transport: success", text
    assert_match "Content: failed", text
    assert_match "Blocking issue: redirect_to_listing", text
    assert_match "Last good content preserved: yes", text
  end

  test "fetch route helper is semantic and stable" do
    assert_equal "/distillator/cache/fetch", fetch_distillator_cache_index_path
    assert_equal "/distillator/cache/preview", preview_distillator_cache_index_path
  end

  test "compatibility view toggle preserves context" do
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = nil
    create_cache(
      normalized_url: "https://example.org/event",
      html: "<html><body>Hello</body></html>",
      http_response_code: 200
    )
    Distillator::FetchCacheStore.expects(:fetch).never

    get distillator_cache_index_path, params: { view: "parity", term: "event", page: "2" }

    assert_response :success
    assert_match "Compatibility view", @response.body
    assert_match "Rich view", @response.body
    assert_match "view=rich", @response.body
    assert_match "view=parity", @response.body
    assert_match "term=event", @response.body
  end

  private

  def visible_text(html)
    document = Nokogiri::HTML(html)
    document.xpath("//script|//style").remove
    document.text.squish
  end

  def create_cache(normalized_url:, html:, http_response_code:)
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(normalized_url),
      normalized_url: normalized_url,
      html: html,
      body: html,
      name: "Cached",
      scrape_date: Time.zone.now,
      successful_refresh: Time.zone.now,
      http_response_code: http_response_code,
      headers: {},
      signals: { "network_status" => "ok", "content_type" => "html" },
      hints: [],
      redirect_chain: []
    )
  end
end
