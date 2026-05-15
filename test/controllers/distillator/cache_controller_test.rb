require "test_helper"

class Distillator::CacheControllerTest < ActionDispatch::IntegrationTest
  setup do
    Distillator::FetchCache.delete_all
    @old_refresh_ui = ENV["DISTILLATOR_CACHE_REFRESH_UI"]
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
  end

  teardown do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = @old_refresh_ui
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
  end

  test "index lists serialized cache rows without fetching" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json"

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal 1, payload.length
    assert_equal cache.id, payload.first["id"]
    assert_equal cache.uri_key, payload.first["uri"]
    assert_equal "1", @response.headers["X-Page"]
    assert_equal "50", @response.headers["X-Per-Page"]
  end

  test "friendly condenser cache index alias works like distillator cache index" do
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/condenser/cache"

    assert_response :success
    assert_match "Condenser Cache", @response.body
  end

  test "friendly condenser cache compare alias works like distillator cache compare" do
    Distillator::CacheCompare.expects(:call).with do |kwargs|
      assert_equal "http://example.org/page", kwargs[:uri]
      assert_nil kwargs[:include_fragment]
      true
    end.returns(
      {
        uri: "http://example.org/page",
        uri_key: "http%3A%2F%2Fexample.org%2Fpage",
        legacy_cache: { html: "<html>legacy</html>" },
        legacy_source: "injected_lookup",
        legacy_lookup_error: nil,
        distillator_cache: { html: "<html>internal</html>" },
        distillator_source: "local_fetch_cache",
        diffs: {},
        missing: { legacy: false, distillator: false }
      }
    )

    get "/condenser/cache/compare", params: { uri: "http://example.org/page" }

    assert_response :success
    assert_match "Cache Comparison", @response.body
  end

  test "cache inspection mode keeps refresh ui disabled without explicit flag" do
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = nil
    create_cache
    assert_read_only_page_does_not_fetch

    get "/distillator/cache"

    assert_response :success
    assert_match "Condenser Cache", @response.body
    assert_match "Scrape date", @response.body
    assert_match "Successful refresh", @response.body
    assert_match "Cache inspection mode. Refresh actions are not available in this environment.", @response.body
    assert_no_match "Fetch URL", @response.body
    assert_no_match %r{button[^>]*>Direct fetch</button>}, @response.body
    assert_match "Apply filters", @response.body
    assert_match "Quick filters", @response.body
    assert_match "Advanced filters", @response.body
    assert_match "URI / Name", @response.body
    assert_match "Health", @response.body
    assert_select 'details[data-operator-context-card]', 0
  end

  test "distillator cache index does not fetch" do
    create_cache
    assert_read_only_page_does_not_fetch

    get "/distillator/cache"

    assert_response :success
  end

  test "cache index uses condenser cache demo-facing language" do
    create_cache(uri: "https://fixtures.example/cache/simple-title")
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache"

    assert_response :success
    assert_match "Condenser Cache", visible_text(@response.body)
    assert_no_match "Distillator", visible_text(@response.body)
    assert_no_match "DISTILLATOR_CACHE_REFRESH_UI", visible_text(@response.body)
    assert_no_match "/distillator/cache", visible_text(@response.body)
    assert_no_match "distillator-dsl", visible_text(@response.body)
  end

  test "explicit refresh ui flag enables operational cache ui" do
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache"

    assert_response :success
    text = visible_text(@response.body)
    assert_match "Condenser Cache", text
    assert_match "Fetch URL", text
    assert_match "Direct fetch", text
    assert_match "Rendered fetch", text
    assert_match "POST fetch", text
    assert_no_match "Read-only cache inspection only", text
    assert_no_match "Refresh actions are disabled", text
    assert_no_match "DISTILLATOR_CACHE_REFRESH_UI", text
  end

  test "cache refresh ui is not enabled just because fetch mode current defaults to internal" do
    ENV["DISTILLATOR_FETCH_MODE"] = nil
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = nil
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache"

    assert_response :success
    text = visible_text(@response.body)
    assert_no_match "Fetch URL", text
    assert_match "Cache inspection mode. Refresh actions are not available in this environment.", text
  end

  test "html index renders fetch url panel with one uri field and three actions" do
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"
    get "/distillator/cache"

    assert_response :success
    assert_select 'form[action="/distillator/cache/fetch"][method="post"] input[type="text"][name="uri"]', 1
    assert_select 'form[action="/distillator/cache/fetch"][method="post"] button[name="fetch_kind"][value="normal"]', text: "Direct fetch"
    assert_select 'form[action="/distillator/cache/fetch"][method="post"] button[name="fetch_kind"][value="rendered"]', text: "Rendered fetch"
    assert_select 'form[action="/distillator/cache/fetch"][method="post"] button[name="fetch_kind"][value="post"]', text: "POST fetch"
  end

  test "compatibility api copy is operational and does not mention preview endpoint" do
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache"

    assert_response :success
    text = visible_text(@response.body)
    assert_match "Compatibility API", text
    assert_match "Legacy-compatible endpoint", text
    assert_match "Cached Wringer-compatible JSON", text
    assert_match "Cache fetch actions", text
    assert_no_match "Cache preview endpoint", text
  end

  test "index shows warning when http succeeded but content failed" do
    create_cache(
      uri: "https://www.ovation.ca/event",
      html: "<html>last good</html>",
      body: "<html>last good</html>",
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "transport_success" => true,
        "content_success" => false,
        "primary_issue_key" => "redirect_to_listing",
        "primary_issue_label" => "Redirect to listing",
        "last_good_preserved_failure" => true
      },
      hints: ["redirect_to_listing", "last_good_preserved_failure"],
      http_response_code: 200,
      successful_refresh: 1.day.ago,
      scrape_date: Time.zone.now
    )
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache"

    assert_response :success
    text = visible_text(@response.body)
    assert_select "span.cache-health-preserved", text: "Preserved"
    assert_match "HTTP 200 but content failed: Redirect to listing", text
    assert_match "Transport: success", text
    assert_match "Content: failed", text
    assert_match "Blocking issue: redirect_to_listing", text
    assert_match "Last good content preserved: yes", text
  end

  test "index renders dominant operator health states across cache rows" do
    create_cache(uri: "https://example.org/healthy")
    create_cache(
      uri: "https://example.org/preserved",
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "transport_success" => true,
        "content_success" => false,
        "primary_issue_key" => "redirect_to_listing",
        "primary_issue_label" => "Redirect to listing",
        "last_good_preserved_failure" => true
      },
      hints: ["redirect_to_listing", "last_good_preserved_failure"],
      http_response_code: 200,
      successful_refresh: 1.day.ago,
      scrape_date: Time.zone.now
    )
    create_cache(
      uri: "https://example.org/warning",
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "transport_success" => true,
        "content_success" => false,
        "primary_issue_key" => "queue_it",
        "primary_issue_label" => "Queue-it waiting room"
      },
      hints: ["queue_it", "waiting_room"],
      http_response_code: 200,
      successful_refresh: Time.zone.now,
      scrape_date: Time.zone.now
    )
    create_cache(
      uri: "https://example.org/failed",
      signals: { "network_status" => "failed", "content_type" => "html" },
      http_response_code: nil
    )
    create_cache(
      uri: "https://example.org/unknown",
      html: nil,
      body: nil,
      signals: {},
      http_response_code: nil,
      scrape_date: nil,
      successful_refresh: nil
    )
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache"

    assert_response :success
    assert_select "span.cache-health-healthy", text: "Healthy"
    assert_select "span.cache-health-preserved", text: "Preserved"
    assert_select "span.cache-health-warning", text: "Warning"
    assert_select "span.cache-health-failed", text: "Failed"
    assert_select "span.cache-health-unknown", text: "Unknown"
  end

  test "show page surfaces transport and content diagnostics for failed content" do
    cache = create_cache(
      uri: "https://www.ovation.ca/event",
      html: "<html>last good</html>",
      body: "<html>last good</html>",
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "transport_success" => true,
        "content_success" => false,
        "primary_issue_key" => "redirect_to_listing",
        "primary_issue_label" => "Redirect to listing",
        "last_good_preserved_failure" => true
      },
      hints: ["redirect_to_listing", "last_good_preserved_failure"],
      http_response_code: 200,
      successful_refresh: 1.day.ago,
      scrape_date: Time.zone.now
    )
    assert_read_only_page_does_not_fetch

    get "/distillator/cache/#{cache.id}"

    assert_response :success
    assert_select 'details[data-operator-context-card]'
    assert_select 'details[data-context-domain="status"]'
    assert_select 'details[data-context-domain="actions"]'
    assert_select 'details[data-context-domain="details"]'
    text = visible_text(@response.body)
    assert_select "span.cache-health-preserved", text: "Preserved"
    assert_match "Operator health:", text
    assert_match "HTTP 200 but content failed: Redirect to listing", text
    assert_match "Transport: success", text
    assert_match "Content: failed", text
    assert_match "Blocking issue: redirect_to_listing", text
    assert_match "Last good preserved: yes", text
  end

  test "cache show keeps condenser cache demo-facing language" do
    cache = create_cache(uri: "https://fixtures.example/cache/show-demo-facing")
    assert_read_only_page_does_not_fetch

    get "/distillator/cache/#{cache.id}"

    assert_response :success
    text = visible_text(@response.body)
    assert_match "Condenser Cache", text
    assert_no_match "new cache", text
    assert_no_match "phase i", text.downcase
    assert_no_match "preview only", text.downcase
    assert_no_match "internal", text.downcase
  end

  test "show page renders failed operator health for blocked cache state" do
    cache = create_cache(
      uri: "https://example.org/blocked",
      html: nil,
      body: nil,
      signals: {
        "network_status" => "blocked",
        "error_type" => "DistillatorFetchBlocked",
        "content_type" => "html",
        "transport_success" => false
      },
      hints: ["blocked"],
      http_response_code: nil,
      successful_refresh: nil,
      scrape_date: Time.zone.now
    )
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/#{cache.id}"

    assert_response :success
    assert_select "span.cache-health-failed", text: "Failed"
  end

  test "compatibility view renders wringer style table headers and preserves post refresh actions" do
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"
    get "/distillator/cache", params: { view: "parity", term: "needle" }

    assert_response :success
    assert_match "Compatibility view", @response.body
    assert_match "Uri", @response.body
    assert_match "HTTP Response", @response.body
    assert_match "Scrape Date", @response.body
    assert_match "Last Successful Refresh", @response.body
    assert_match "Page Name", @response.body
    assert_match "Html", @response.body
    assert_match "Operations", @response.body
    assert_match "Fetch actions", @response.body
    assert_select 'form[action="/distillator/cache/fetch"][method="post"]', minimum: 1
  end

  test "top level normal fetch calls fetch cache store through command semantics" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"

    fetch_result = OpenStruct.new(normalized_url: "http://example.org/events", http_response_code: 200, cache_reason: "force_scrape", fetch_path: "legacy", html: "<html>body</html>", cache: nil)
    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "http://example.org/events", kwargs[:uri]
      assert_equal true, kwargs[:force_scrape]
      assert_equal false, kwargs[:use_phantomjs]
      assert_equal false, kwargs[:json_post]
      true
    end.returns(fetch_result)

    post "/distillator/cache/fetch", params: { uri: "http://example.org/events", fetch_kind: "normal" }

    assert_redirected_to "/distillator/cache"
    follow_redirect!
    assert_match "Fetched Direct fetch for http://example.org/events", @response.body
    assert_match "HTTP 200", @response.body
    assert_match "path legacy", @response.body
    assert_match "cache refresh forced", @response.body
    assert_match "HTML written", @response.body
  end

  test "successful fetch shows structured last action result on index" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"

    fetch_result = OpenStruct.new(
      normalized_url: "http://example.org/events",
      http_response_code: 200,
      cache_reason: "force_scrape",
      fetch_path: "legacy",
      html: "<html>body</html>",
      cache: nil
    )

    Distillator::FetchCacheStore.expects(:fetch).returns(fetch_result)

    post "/distillator/cache/fetch", params: {
      uri: "http://example.org/events",
      fetch_kind: "normal"
    }

    assert_redirected_to "/distillator/cache"
    follow_redirect!

    assert_response :success
    assert_match "Last Action Result", @response.body
    assert_match "Fetch mode:</strong> Direct fetch", @response.body
    assert_match "Normalized URL:</strong> http://example.org/events", @response.body
    assert_match "HTTP response code:</strong> 200", @response.body
    assert_match "Fetch path:</strong> legacy", @response.body
    assert_match "Cache reason:</strong> force_scrape", @response.body
    assert_match "HTML result:</strong> HTML written", @response.body
  end

  test "successful rendered fetch shows rendered fetch label in last action result" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"

    Distillator::FetchCacheStore.expects(:fetch).returns(
      OpenStruct.new(
        normalized_url: "http://example.org/rendered",
        http_response_code: 200,
        cache_reason: "force_scrape",
        fetch_path: "legacy",
        html: "<html>rendered</html>",
        cache: nil
      )
    )

    post "/distillator/cache/fetch", params: {
      uri: "http://example.org/rendered",
      fetch_kind: "rendered"
    }

    follow_redirect!

    assert_match "Last Action Result", @response.body
    assert_match "Fetch mode:</strong> Rendered fetch", @response.body
  end

  test "top level fetch defaults missing fetch kind to normal" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"

    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal false, kwargs[:use_phantomjs]
      assert_equal false, kwargs[:json_post]
      true
    end.returns(OpenStruct.new(normalized_url: "http://example.org/default", http_response_code: 200, cache_reason: "force_scrape", fetch_path: "cache", html: "<html></html>", cache: nil))

    post "/distillator/cache/fetch", params: { uri: "http://example.org/default" }

    assert_redirected_to "/distillator/cache"
  end

  test "top level rendered fetch calls phantomjs and include fragment" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"

    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "http://example.org/rendered", kwargs[:uri]
      assert_equal true, kwargs[:force_scrape]
      assert_equal true, kwargs[:use_phantomjs]
      assert_equal true, kwargs[:include_fragment]
      assert_equal false, kwargs[:json_post]
      true
    end.returns(OpenStruct.new(normalized_url: "http://example.org/rendered", cache: nil))

    post "/distillator/cache/fetch", params: { uri: "http://example.org/rendered", fetch_kind: "rendered" }

    assert_redirected_to "/distillator/cache"
  end

  test "top level post fetch calls json_post" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"

    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "http://example.org/post", kwargs[:uri]
      assert_equal true, kwargs[:force_scrape]
      assert_equal true, kwargs[:json_post]
      true
    end.returns(OpenStruct.new(normalized_url: "http://example.org/post", cache: nil))

    post "/distillator/cache/fetch", params: { uri: "http://example.org/post", fetch_kind: "post" }

    assert_redirected_to "/distillator/cache"
  end

  test "cache index does not expose preview first actions in operational mode" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache"

    assert_response :success
    text = visible_text(@response.body)
    assert_match "Compare", text
    assert_match "Direct fetch", text
    assert_match "Rendered fetch", text
    assert_match "POST fetch", text
    assert_match "View", text
    assert_match "Diagnose", text
    assert_match "Refresh", text
    assert_no_match "Preview Direct fetch", text
    assert_no_match "Preview Rendered fetch", text
    assert_no_match "Preview POST", text
    assert_no_match "Cache preview endpoint", text
    assert_no_match "Preview JSON endpoint", text
    assert_match "/distillator/cache/#{cache.id}", @response.body
  end

  test "show page does not expose preview first actions in operational mode" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/#{cache.id}"

    assert_response :success
    text = visible_text(@response.body)
    assert_match "Condenser Cache Detail", text
    assert_no_match "Preview Direct fetch", text
    assert_no_match "Preview Rendered fetch", text
    assert_no_match "Preview POST", text
    assert_no_match "Cache preview endpoint", text
    assert_select 'form[action="/distillator/cache/fetch"][method="post"] input[type="submit"][value="Direct fetch"]', 1
    assert_select 'form[action="/distillator/cache/fetch"][method="post"] input[type="submit"][value="Rendered fetch"]', 1
    assert_select 'form[action="/distillator/cache/fetch"][method="post"] input[type="submit"][value="POST fetch"]', 1
  end

  test "show page includes copyable compatibility links and omits edit destroy" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/#{cache.id}"

    assert_response :success
    assert_match "Compatibility API", @response.body
    assert_match "/websites/wring.json?uri=http%3A%2F%2Fexample.org%2Fcached", @response.body
    assert_match "Cached Wringer-compatible JSON", @response.body
    assert_match "Open raw cached HTML", @response.body
    assert_match "Open cached Wringer-compatible JSON", @response.body
    assert_match "Open cache comparison", @response.body
    assert_match "data-copy-url", @response.body
    assert_no_match ">Edit<", @response.body
    assert_no_match ">Destroy<", @response.body
    assert_match "Refresh instead of edit or destroy", @response.body
  end

  test "cache show page uses condenser cache demo-facing language" do
    cache = create_cache(uri: "https://fixtures.example/cache/simple-title")
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/#{cache.id}"

    assert_response :success
    assert_match "Condenser Cache Detail", visible_text(@response.body)
    assert_no_match "Distillator", visible_text(@response.body)
    assert_no_match "/distillator/cache", visible_text(@response.body)
  end

  test "row wring action preserves filter context and calls normal fetch" do
    cache = create_cache(uri: "http://example.org/filtered")
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"

    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal cache.normalized_url, kwargs[:uri]
      assert_equal true, kwargs[:force_scrape]
      assert_equal false, kwargs[:use_phantomjs]
      assert_equal false, kwargs[:json_post]
      true
    end.returns(OpenStruct.new(normalized_url: cache.normalized_url, cache: nil))

    post "/distillator/cache/fetch", params: {
      uri: cache.normalized_url,
      fetch_kind: "normal",
      term: "needle",
      health: "healthy",
      status_group: "2xx",
      has_html: "true",
      content_type: "html",
      network_status: "ok",
      redirected: "false",
      hint: "json",
      sort: "updated_at",
      direction: "desc",
      page: "2",
      per_page: "25"
    }

    assert_redirected_to "/distillator/cache?content_type=html&direction=desc&has_html=true&health=healthy&hint=json&network_status=ok&page=2&per_page=25&redirected=false&sort=updated_at&status_group=2xx&term=needle"
  end

  test "invalid fetch returns to filtered list with error and does not call fetch" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"
    Distillator::FetchCacheStore.expects(:fetch).never

    post "/distillator/cache/fetch", params: { uri: "", fetch_kind: "normal", term: "needle", page: "3" }

    assert_redirected_to "/distillator/cache?page=3&term=needle"
    follow_redirect!
    assert_match "URI is invalid", @response.body
    assert_match "Direct fetch for", @response.body
    assert_match "No fetch performed", @response.body
    assert_no_match "Last Action Result", @response.body
  end

  test "failed fetch does not show last action result" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"
    Distillator::FetchCacheStore.expects(:fetch).never

    post "/distillator/cache/fetch", params: {
      uri: "",
      fetch_kind: "normal"
    }

    follow_redirect!

    assert_match "No fetch performed", @response.body
    assert_no_match "Last Action Result", @response.body
  end

  test "successful fetch preserves filters and shows last action result" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"

    Distillator::FetchCacheStore.expects(:fetch).returns(
      OpenStruct.new(
        normalized_url: "http://example.org/filtered",
        http_response_code: 200,
        cache_reason: "force_scrape",
        fetch_path: "legacy",
        html: "<html>body</html>",
        cache: nil
      )
    )

    post "/distillator/cache/fetch", params: {
      uri: "http://example.org/filtered",
      fetch_kind: "normal",
      term: "needle",
      health: "healthy",
      page: "2",
      per_page: "25"
    }

    assert_redirected_to "/distillator/cache?health=healthy&page=2&per_page=25&term=needle"
    follow_redirect!

    assert_match "Last Action Result", @response.body
    assert_select 'input[name="term"][value=?]', "needle"
  end

  test "html index renders current filters without fetching" do
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache", params: {
      term: "needle",
      http_response_code: "404",
      has_html: "false",
      network_status: "failed",
      sort: "updated_at",
      direction: "desc"
    }

    assert_redirected_to "/distillator/cache?has_html=false&http_response_code=404&network_status=failed&term=needle"

    follow_redirect!
    assert_response :success
    assert_select 'input[name="term"][value=?]', "needle"
    assert_select 'input[name="http_response_code"][value=?]', "404"
    assert_select 'select[name="has_html"] option[selected="selected"][value=?]', "false"
    assert_select 'input[name="network_status"][value=?]', "failed"
    assert_select 'input[name="sort"][value=?]', "updated_at"
    assert_select 'input[name="direction"][value=?]', "desc"
  end

  test "html index filter form intentionally preserves current sort and direction like websites" do
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache", params: {
      term: "needle",
      sort: "http_response_code",
      direction: "asc"
    }

    assert_response :success
    assert_select 'form[action="/distillator/cache"][method="get"] input[type="hidden"][name="sort"][value=?]', "http_response_code"
    assert_select 'form[action="/distillator/cache"][method="get"] input[type="hidden"][name="direction"][value=?]', "asc"
  end

  test "json index filters by term without fetching" do
    matching = create_cache(uri: "http://example.org/needle", name: "Alpha")
    create_cache(uri: "http://example.org/other", name: "Beta")
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { term: "needle" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal [matching.id], payload.map { |row| row["id"] }
  end

  test "json index filters by http_response_code without fetching" do
    matching = create_cache(uri: "http://example.org/not-found", http_response_code: 404)
    create_cache(uri: "http://example.org/success", http_response_code: 200)
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { http_response_code: "404" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal [matching.id], payload.map { |row| row["id"] }
  end

  test "json index ignores blank http_response_code without fetching" do
    first = create_cache(uri: "http://example.org/first", http_response_code: 404)
    second = create_cache(uri: "http://example.org/second", http_response_code: 200)
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { http_response_code: "" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal [first.id, second.id].sort, payload.map { |row| row["id"] }.sort
  end

  test "json index ignores invalid http_response_code without fetching" do
    zero = create_cache(uri: "http://example.org/zero", http_response_code: 0)
    other = create_cache(uri: "http://example.org/other", http_response_code: 404)
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { http_response_code: "abc" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal [zero.id, other.id].sort, payload.map { |row| row["id"] }.sort
  end

  test "json index trims numeric http_response_code without fetching" do
    matching = create_cache(uri: "http://example.org/not-found-trimmed", http_response_code: 404)
    create_cache(uri: "http://example.org/success-trimmed", http_response_code: 200)
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { http_response_code: " 404 " }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal [matching.id], payload.map { |row| row["id"] }
  end

  test "json index filters by has_html without fetching" do
    matching = create_cache(uri: "http://example.org/with-html", html: "<html>present</html>")
    create_cache(uri: "http://example.org/without-html", html: nil, body: nil)
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { has_html: "true" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal [matching.id], payload.map { |row| row["id"] }
  end

  test "json index filters by network_status without fetching" do
    matching = create_cache(uri: "http://example.org/failed", signals: { "network_status" => "failed" })
    create_cache(uri: "http://example.org/ok", signals: { "network_status" => "ok" })
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { network_status: "failed" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal [matching.id], payload.map { |row| row["id"] }
  end

  test "json index filters redirected false without fetching" do
    direct = create_cache(uri: "http://example.org/direct", final_url: "http://example.org/direct", redirect_chain: [])
    create_cache(
      uri: "http://example.org/redirected",
      final_url: "https://example.org/final",
      redirect_chain: ["http://example.org/redirected", "https://example.org/final"]
    )
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { redirected: "false" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal [direct.id], payload.map { |row| row["id"] }
  end

  test "json index paginates with conservative default without fetching" do
    55.times do |index|
      create_cache(uri: "http://example.org/cache-#{index}")
    end
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json"

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal 50, payload.length
    assert_equal "1", @response.headers["X-Page"]
    assert_equal "50", @response.headers["X-Per-Page"]
    assert_equal "55", @response.headers["X-Total-Count"]
    assert_equal "2", @response.headers["X-Total-Pages"]
  end

  test "json index respects page and per_page without fetching" do
    5.times do |index|
      create_cache(uri: "http://example.org/page-#{index}")
    end
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { page: "2", per_page: "2" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal 2, payload.length
    assert_equal "2", @response.headers["X-Page"]
    assert_equal "2", @response.headers["X-Per-Page"]
    assert_equal "5", @response.headers["X-Total-Count"]
    assert_equal "3", @response.headers["X-Total-Pages"]
  end

  test "json index respects sort and direction without fetching" do
    low = create_cache(uri: "http://example.org/low", http_response_code: 200)
    high = create_cache(uri: "http://example.org/high", http_response_code: 404)
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { sort: "http_response_code", direction: "asc" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal [low.id, high.id], payload.map { |row| row["id"] }
  end

  test "json index falls back safely for invalid sort and direction without fetching" do
    first = create_cache(uri: "http://example.org/first-safe", updated_at: 2.days.ago)
    second = create_cache(uri: "http://example.org/second-safe")
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { sort: "bogus", direction: "sideways" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal [second.id, first.id], payload.map { |row| row["id"] }
  end

  test "json index sorts by normalized_url without fetching" do
    alpha = create_cache(uri: "http://example.org/a")
    beta = create_cache(uri: "http://example.org/b")
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { sort: "normalized_url", direction: "asc" }

    assert_response :success
    assert_equal [alpha.id, beta.id], JSON.parse(@response.body).map { |row| row["id"] }
  end

  test "json index sorts by html_bytes without fetching" do
    small = create_cache(uri: "http://example.org/small", html: "<p>x</p>", body: "<p>x</p>")
    large = create_cache(uri: "http://example.org/large", html: "<div>#{'x' * 20}</div>", body: "<div>#{'x' * 20}</div>")
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { sort: "html_bytes", direction: "desc" }

    assert_response :success
    assert_equal [large.id, small.id], JSON.parse(@response.body).map { |row| row["id"] }
  end

  test "html index next page link preserves existing filters and per_page" do
    3.times do |index|
      create_cache(
        uri: "http://example.org/needle-#{index}",
        http_response_code: 404,
        signals: { "network_status" => "failed" }
      )
    end
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache", params: {
      term: "needle",
      http_response_code: "404",
      has_html: "true",
      network_status: "failed",
      per_page: "2"
    }

    assert_response :success
    assert_match '/distillator/cache?has_html=true&amp;http_response_code=404&amp;network_status=failed&amp;page=2&amp;per_page=2&amp;term=needle', @response.body
  end

  test "html index previous page link preserves existing filters and per_page" do
    3.times do |index|
      create_cache(
        uri: "http://example.org/needle-prev-#{index}",
        http_response_code: 404,
        signals: { "network_status" => "failed" }
      )
    end
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache", params: {
      term: "needle-prev",
      http_response_code: "404",
      has_html: "true",
      network_status: "failed",
      per_page: "2",
      page: "2"
    }

    assert_response :success
    assert_match '/distillator/cache?has_html=true&amp;http_response_code=404&amp;network_status=failed&amp;page=1&amp;per_page=2&amp;term=needle-prev', @response.body
  end

  test "show returns serialized cache row without fetching" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/#{cache.id}.json"

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal cache.id, payload["id"]
    assert_equal cache.uri_key, payload["uri_key"]
  end

  test "show json can expose preview refresh diagnostics" do
    cache = create_cache(signals: { "network_status" => "ok", "content_type" => "html", "redirect_type" => "none", "fetch_path" => "legacy", "native_ineligible_reason" => "json_post" })
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    get "/distillator/cache/#{cache.id}.json", params: { preview: "true", force_scrape_every_hrs: "0" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal "legacy", payload["fetch_path"]
    assert_equal "json_post", payload["native_ineligible_reason"]
    assert_equal true, payload["preview"]["would_refresh"]
    assert_equal "stale_by_force_scrape_every_hrs", payload["preview"]["reason"]
  end

  test "html show renders operator cards and secondary diagnostics without fetching" do
    cache = create_cache(signals: { "network_status" => "ok", "content_type" => "html", "redirect_type" => "none", "fetch_path" => "legacy", "native_ineligible_reason" => "json_post" })
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/#{cache.id}"

    assert_response :success
    assert_match "Status card", @response.body
    assert_match "Identity card", @response.body
    assert_match "Last fetch card", @response.body
    assert_match "Content card", @response.body
    assert_match "Diagnostics card", @response.body
    assert_match "Compatibility card", @response.body
    assert_match "Operator health:", @response.body
    assert_match "Fetch path:", @response.body
    assert_match "Native ineligible reason:", @response.body
    assert_match "Content preview:", @response.body
    assert_match "/distillator/cache/#{cache.id}/raw_view", @response.body
    assert_match "/distillator/cache/#{cache.id}/wring_json_view", @response.body
    assert_match "/distillator/cache/compare?uri=", @response.body
    assert_no_match "Preview Direct fetch", visible_text(@response.body)
  end

  test "html show shows row refresh actions only when feature flag is enabled" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"
    get "/distillator/cache/#{cache.id}"

    assert_response :success
    assert_match "Direct fetch", @response.body
    assert_match "Rendered fetch", @response.body
    assert_match "POST fetch", @response.body
  end

  test "html show can render inline preview without fetching" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    get "/distillator/cache/#{cache.id}", params: { preview: "true", force_scrape_every_hrs: "0" }

    assert_response :success
    assert_match "Refresh Preview", @response.body
    assert_match "Would refresh?</strong> true", @response.body
    assert_match "Reason:</strong> stale_by_force_scrape_every_hrs", @response.body
  end

  test "raw renders cached html only without fetching and applies safety headers" do
    cache = create_cache(html: "<html><head><script>alert(1)</script></head><body>cached raw</body></html>")
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/#{cache.id}/raw"

    assert_response :success
    assert_equal "<html><head><script>alert(1)</script></head><body>cached raw</body></html>", @response.body
    assert_equal "text/html; charset=utf-8", @response.headers["Content-Type"]
    assert_equal "nosniff", @response.headers["X-Content-Type-Options"]
    assert_includes @response.headers["Content-Security-Policy"], "sandbox"
    assert_nil @response.headers["X-Frame-Options"]
  end

  test "raw view page shows warning and timestamps without fetching" do
    cache = create_cache(html: "<html>cached raw</html>")
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/#{cache.id}/raw_view"

    assert_response :success
    assert_match "Raw Cached HTML", @response.body
    assert_match "cached HTML only; no refresh performed.", @response.body
    assert_match "sandboxed to reduce app-origin script execution", @response.body
    assert_match "Scrape date:", @response.body
    assert_match "Successful refresh:", @response.body
    assert_match "/distillator/cache/#{cache.id}/raw", @response.body
    assert_no_match "Distillator", visible_text(@response.body)
  end

  test "wring_json returns exact legacy keys from cache only" do
    cache = create_cache(
      html: "<html>cached json</html>",
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "redirect_type" => "normal",
        "redirected" => true,
        "final_url" => "https://example.org/final"
      },
      hints: ["hint"],
      final_url: "https://example.org/final",
      redirect_chain: ["http://example.org/cached", "https://example.org/final"],
      http_response_code: 404
    )
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/#{cache.id}/wring_json"

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal %w[final_url hints html http_code redirect_chain signals].sort, payload.keys.sort
    assert_equal "<html>cached json</html>", payload["html"]
    assert_equal "ok", payload["signals"]["network_status"]
    assert_equal "html", payload["signals"]["content_type"]
    assert_equal "normal", payload["signals"]["redirect_type"]
    assert_equal true, payload["signals"]["redirected"]
    assert_equal "https://example.org/final", payload["signals"]["final_url"]
    assert_equal 404, payload["http_code"]
    assert_nil @response.headers["X-Frame-Options"]
  end

  test "wring json view shows exact cached payload without fetching" do
    cache = create_cache(
      html: "<html>cached json</html>",
      signals: { "network_status" => "ok" },
      hints: ["hint"],
      final_url: "https://example.org/final",
      redirect_chain: ["http://example.org/cached", "https://example.org/final"],
      http_response_code: 404
    )
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/#{cache.id}/wring_json_view"

    assert_response :success
    assert_match "Cached Wringer-compatible JSON", @response.body
    assert_match "&quot;html&quot;: &quot;&lt;html&gt;cached json&lt;/html&gt;&quot;", @response.body
    assert_match "&quot;http_code&quot;: 404", @response.body
    assert_match "/distillator/cache/#{cache.id}/wring_json", @response.body
    assert_no_match "Distillator", visible_text(@response.body)
  end

  test "cache preview page uses neutral cache language" do
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/preview", params: {
      uri: "https://example.org/events",
      fetch_kind: "normal"
    }

    assert_response :success
    assert_match "Internal Cache Refresh Diagnostic", @response.body
    assert_match "Diagnostic JSON", @response.body
    assert_no_match "Distillator", visible_text(@response.body)
    assert_no_match "/distillator/cache", visible_text(@response.body)
  end

  test "preview returns missing cache reason without fetching" do
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    get "/distillator/cache/preview.json", params: { uri: "http://example.org/missing" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal true, payload["would_refresh"]
    assert_equal "missing_cache", payload["reason"]
  end

  test "preview returns fresh cache reason without fetching" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    get "/distillator/cache/preview.json", params: { uri: cache.normalized_url, force_scrape_every_hrs: "200000" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal false, payload["would_refresh"]
    assert_equal "fresh_cache", payload["reason"]
  end

  test "preview returns force_scrape reason without fetching" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    get "/distillator/cache/preview.json", params: { uri: cache.normalized_url, force_scrape: "true" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal true, payload["would_refresh"]
    assert_equal "force_scrape", payload["reason"]
  end

  test "preview returns threshold zero refresh reason without fetching" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    get "/distillator/cache/preview.json", params: { uri: cache.normalized_url, force_scrape_every_hrs: "0" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal true, payload["would_refresh"]
    assert_equal "stale_by_force_scrape_every_hrs", payload["reason"]
  end

  test "preview returns invalid uri without fetching" do
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/preview.json", params: { uri: "http://[invalid" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal false, payload["would_refresh"]
    assert_equal "invalid_uri", payload["reason"]
  end

  test "preview returns invalid uri for missing uri without fetching" do
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/preview.json"

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal false, payload["would_refresh"]
    assert_equal "invalid_uri", payload["reason"]
  end

  test "preview returns blocked url without fetching" do
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchGuard.stubs(:check_url).returns(
      Distillator::FetchGuard::Result.new(
        allowed: false,
        error: "Blocked URL host with no DNS resolution result: missing.example",
        reason: :dns_resolution_failed
      )
    )

    get "/distillator/cache/preview.json", params: { uri: "http://127.0.0.1" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal false, payload["would_refresh"]
    assert_equal "blocked_url", payload["reason"]
    assert_equal "dns_resolution_failed", payload["guard_reason"]
    assert_includes payload["guard_error"], "no DNS resolution result"
  end

  test "fetch redirects back with notice after successful request" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"
    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "http://example.org/events", kwargs[:uri]
      assert_equal true, kwargs[:include_fragment]
      assert_equal true, kwargs[:force_scrape]
      assert_equal "24", kwargs[:force_scrape_every_hrs]
      assert_equal true, kwargs[:use_phantomjs]
      assert_equal false, kwargs[:json_post]
      assert_equal true, kwargs[:absolute_src]
      true
    end.returns(OpenStruct.new(normalized_url: "http://example.org/events", cache: nil))

    post "/distillator/cache/fetch", params: {
      uri: "http://example.org/events",
      fetch_kind: "rendered",
      include_fragment: "true",
      force_scrape: "true",
      force_scrape_every_hrs: "24",
      absolute_src: "true"
    }

    assert_redirected_to "/distillator/cache"
  end

  test "fetch rejects invalid uri without fetching" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"
    Distillator::FetchCacheStore.expects(:fetch).never

    post "/distillator/cache/fetch", params: { uri: "http://[invalid", fetch_kind: "normal" }

    assert_redirected_to "/distillator/cache"
  end

  test "fetch rejects blocked url without fetching" do
    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: false, error: "blocked"))

    post "/distillator/cache/fetch", params: { uri: "http://127.0.0.1/events", fetch_kind: "normal" }

    assert_redirected_to "/distillator/cache"
  end

  test "diagnostic preview html still shows refresh decision without fetching" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    get "/distillator/cache/preview", params: { uri: cache.normalized_url, force_scrape: "true" }

    assert_response :success
    text = visible_text(@response.body)
    assert_match "Internal Cache Refresh Diagnostic", text
    assert_match "No fetch is performed from this page", text
    assert_match "Would refresh?", text
    assert_match "force_scrape", text
  end

  test "preview html shows chosen fetch mode and threshold zero details without fetching" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    get "/distillator/cache/preview", params: { uri: cache.normalized_url, fetch_kind: "rendered", force_scrape_every_hrs: "0" }

    assert_response :success
    assert_match "Chosen fetch mode:</strong> Rendered fetch (rendered)", @response.body
    assert_match "Would refresh?</strong> true", @response.body
    assert_match "Reason:</strong> stale_by_force_scrape_every_hrs", @response.body
  end

  test "preview page includes final post action when refresh ui is enabled" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    ENV["DISTILLATOR_CACHE_REFRESH_UI"] = "true"
    get "/distillator/cache/preview", params: { uri: cache.normalized_url, fetch_kind: "post", force_scrape_every_hrs: "0" }

    assert_response :success
    assert_select 'form[action="/distillator/cache/fetch"][method="post"] input[type="submit"][value="POST fetch"]', 1
  end

  test "preview html shows force scrape every hrs effects without fetching" do
    cache = create_cache
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    get "/distillator/cache/preview", params: { uri: cache.normalized_url, force_scrape_every_hrs: "0" }

    assert_response :success
    assert_match "Would refresh?</strong> true", @response.body
    assert_match "Reason:</strong> stale_by_force_scrape_every_hrs", @response.body
  end

  test "preview html with no uri renders form without crashing" do
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache/preview"

    assert_response :success
    assert_match "Internal Cache Refresh Diagnostic", @response.body
    assert_match "Run diagnostic", @response.body
    assert_no_match "Diagnostic Result", @response.body
  end

  test "compare page rescue fallback shows source labels and error context" do
    assert_read_only_page_does_not_fetch
    Distillator::CacheCompare.stubs(:call).raises(StandardError, "boom")

    get "/distillator/cache/compare", params: { uri: "http://example.org/failure" }

    assert_response :unprocessable_entity
    assert_match "Legacy source:</strong> unavailable", @response.body
    assert_match "Legacy lookup error:</strong> Unexpected comparison failure", @response.body
    assert_match "Condenser source:</strong> local_fetch_cache", @response.body
  end

  test "json index filters by health without fetching" do
    matching = create_cache(uri: "http://example.org/network-failed", signals: { "network_status" => "failed" })
    create_cache(uri: "http://example.org/healthy")
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { health: "network_failed" }

    assert_response :success
    assert_equal [matching.id], JSON.parse(@response.body).map { |row| row["id"] }
  end

  test "json index filters by status group without fetching" do
    matching = create_cache(uri: "http://example.org/4xx", http_response_code: 404)
    create_cache(uri: "http://example.org/2xx", http_response_code: 200)
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { status_group: "4xx" }

    assert_response :success
    assert_equal [matching.id], JSON.parse(@response.body).map { |row| row["id"] }
  end

  test "json index filters by nil status group without fetching" do
    matching = create_cache(uri: "http://example.org/nil-code", http_response_code: nil)
    create_cache(uri: "http://example.org/not-nil", http_response_code: 200)
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { status_group: "nil" }

    assert_response :success
    assert_equal [matching.id], JSON.parse(@response.body).map { |row| row["id"] }
  end

  test "json index filters by content type without fetching" do
    matching = create_cache(uri: "http://example.org/json", signals: { "content_type" => "json" })
    create_cache(uri: "http://example.org/html", signals: { "content_type" => "html" })
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { content_type: "json" }

    assert_response :success
    assert_equal [matching.id], JSON.parse(@response.body).map { |row| row["id"] }
  end

  test "json index filters by hint without fetching" do
    matching = create_cache(uri: "http://example.org/empty", hints: ["empty_body"])
    create_cache(uri: "http://example.org/full", hints: ["json_detected"])
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { hint: "empty_body" }

    assert_response :success
    assert_equal [matching.id], JSON.parse(@response.body).map { |row| row["id"] }
  end

  test "json index filters by redirected without fetching" do
    matching = create_cache(uri: "http://example.org/source", final_url: "http://example.org/final", redirect_chain: ["http://example.org/source", "http://example.org/final"])
    create_cache(uri: "http://example.org/direct", final_url: "http://example.org/direct", redirect_chain: [])
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { redirected: "true" }

    assert_response :success
    assert_equal [matching.id], JSON.parse(@response.body).map { |row| row["id"] }
  end

  test "json index filters by last attempt without fetching" do
    matching = create_cache(uri: "http://example.org/never-attempted", scrape_date: nil)
    create_cache(uri: "http://example.org/attempted")
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { last_attempt: "never" }

    assert_response :success
    assert_equal [matching.id], JSON.parse(@response.body).map { |row| row["id"] }
  end

  test "json index filters by last success without fetching" do
    matching = create_cache(uri: "http://example.org/never-success", successful_refresh: nil)
    create_cache(uri: "http://example.org/with-success")
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { last_success: "never" }

    assert_response :success
    assert_equal [matching.id], JSON.parse(@response.body).map { |row| row["id"] }
  end

  test "html index renders quick filters and badges without fetching" do
    create_cache(uri: "http://example.org/network", signals: { "network_status" => "failed" })
    create_cache(uri: "http://example.org/json", signals: { "content_type" => "json" })
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache"

    assert_response :success
    assert_match "Quick filters", @response.body
    assert_match "Healthy", @response.body
    assert_match "Needs review", @response.body
    assert_match "Failed", @response.body
    assert_match "Network failed", @response.body
    assert_match "JSON", @response.body
    assert_match "cache-badge-health", @response.body
    assert_match "cache-badge-html", @response.body
  end

  test "html sortable links preserve filters" do
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache", params: { term: "needle", health: "healthy", per_page: "25" }

    assert_response :success
    assert_match "term=needle", @response.body
    assert_match "health=healthy", @response.body
    assert_select 'input[type="hidden"][name="per_page"][value=?]', "25"
  end

  test "html index does not include hidden per_page when default pagination is active" do
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache"

    assert_response :success
    assert_select 'input[type="hidden"][name="per_page"]', 0
  end

  test "html index uses advanced filters details and preserves filter controls" do
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache"

    assert_response :success
    assert_harmonized_table_shell
    assert_harmonized_filter_form(action: "/distillator/cache")
    assert_harmonized_filter_shell
    assert_harmonized_advanced_filters
    assert_select "table thead tr", 1
    assert_select "table thead tr th:nth-child(1)", text: /Health/
    assert_harmonized_sortable_header(label: "URI / Name", sort_key: "normalized_url")
    assert_harmonized_sortable_header(label: "HTTP", sort_key: "http_response_code")
    assert_harmonized_apply_filters_button
    assert_harmonized_reset_filters_link(params: { view: "rich" })
  end

  test "html index shows summary cards before advanced filters" do
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache"

    assert_response :success
    assert_match "Healthy", @response.body
    assert_match "Advanced filters", @response.body
    assert_harmonized_summary_cards_before_filters
  end

  test "html sortable links toggle direction and preserve filters" do
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache", params: { term: "needle", health: "healthy", http_response_code: "404", direction: "asc", sort: "http_response_code", per_page: "25" }

    assert_response :success
    assert_match /sort=http_response_code/, @response.body
    assert_match /direction=desc/, @response.body
    assert_sort_link_preserves_filters(
      label: "HTTP",
      sort_key: "http_response_code",
      params: {
        term: "needle",
        health: "healthy",
        http_response_code: "404",
        per_page: "25"
      }
    )
  end

  test "show page matches harmonized record card contract" do
    cache = create_cache
    assert_read_only_page_does_not_fetch

    get "/distillator/cache/#{cache.id}"

    assert_response :success
    assert_harmonized_record_card
    assert_harmonized_card_action_bar
  end

  test "distillator cache show does not fetch" do
    cache = create_cache
    assert_read_only_page_does_not_fetch

    get "/distillator/cache/#{cache.id}"

    assert_response :success
  end

  test "html index canonical redirect strips blank filters" do
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache", params: { term: "", has_html: "", page: "0" }

    assert_redirected_to "/distillator/cache"
  end

  test "html index canonical redirect normalizes invalid page and per_page" do
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache", params: { term: "needle", page: "-2", per_page: "500" }

    assert_redirected_to "/distillator/cache?per_page=100&term=needle"
  end

  test "html index canonical redirect removes invalid sort and direction" do
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache", params: { term: "needle", sort: "bogus", direction: "sideways" }

    assert_redirected_to "/distillator/cache?term=needle"
  end

  test "json index keeps array response and pagination headers with normalized params" do
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache.json", params: { term: "", page: "0", per_page: "500", sort: "bogus", direction: "sideways" }

    assert_response :success
    assert_kind_of Array, JSON.parse(@response.body)
    assert_equal "1", @response.headers["X-Page"]
    assert_equal "100", @response.headers["X-Per-Page"]
    assert_equal "1", @response.headers["X-Total-Count"]
    assert_equal "1", @response.headers["X-Total-Pages"]
  end

  test "compare page renders differences without fetching" do
    assert_read_only_page_does_not_fetch
    Distillator::CacheCompare.expects(:call).returns(
      {
        uri: "http://example.org/page",
        uri_key: CGI.escape("http://example.org/page"),
        legacy_cache: { html: "<html>legacy</html>" },
        legacy_source: "injected_lookup",
        legacy_lookup_error: nil,
        distillator_cache: { html: "<html>internal</html>" },
        distillator_source: "local_fetch_cache",
        diffs: { html_sha256: { same: false, classification: :blocking_regression, legacy: "a", distillator: "b" } },
        missing: { legacy: false, distillator: false },
        summary: {
          same: false,
          promotable: false,
          http_code_difference: false,
          final_url_difference: false,
          content_type_difference: false,
          html_hash_difference: true,
          body_byte_difference: false,
          title_difference: false,
          blocking_regressions: [:html_sha256],
          improvements: [],
          metadata_only_diffs: [],
          unknown_diffs: []
        }
      }
    )

    get "/distillator/cache/compare", params: { uri: "http://example.org/page" }

    assert_response :success
    assert_match "Cache Comparison", @response.body
    assert_match "Migration confidence", @response.body
    assert_match "Promotable:", @response.body
    assert_match "Blocking regressions:", @response.body
    assert_match "Legacy source:", @response.body
    assert_match "Condenser source:", @response.body
    assert_match "Condenser cache missing:", @response.body
    assert_match "<th>Condenser</th>", @response.body
    assert_match "No cache refresh was performed.", @response.body
    assert_match "html_sha256", @response.body
    assert_match "blocking_regression", @response.body
    assert_match "Raw payloads", @response.body
    assert_no_match "New source", visible_text(@response.body)
    assert_no_match "New cache", visible_text(@response.body)
    assert_no_match "Distillator", visible_text(@response.body)
  end

  test "cache index stays operational and does not fetch under heavy filter and sort usage" do
    3.times do |index|
      create_cache(
        uri: "http://example.org/heavy-#{index}",
        http_response_code: 404,
        signals: { "network_status" => "failed", "content_type" => "json" },
        hints: ["empty_body"],
        final_url: "http://example.org/final-#{index}",
        redirect_chain: ["http://example.org/heavy-#{index}", "http://example.org/final-#{index}"]
      )
    end
    Distillator::FetchCacheStore.expects(:fetch).never

    get "/distillator/cache", params: {
      term: "heavy",
      http_response_code: "404",
      has_html: "true",
      network_status: "failed",
      health: "network_failed",
      status_group: "4xx",
      content_type: "json",
      hint: "empty_body",
      redirected: "true",
      last_attempt: "last_7d",
      last_success: "last_7d",
      sort: "http_response_code",
      direction: "asc",
      page: "1",
      per_page: "2"
    }

    follow_redirect! if response.redirect?
    assert_response :success
    assert_match "Apply filters", @response.body
    assert_match "Network failed", @response.body
    assert_match "cache-badge-health", @response.body
    assert_match "direction=desc", @response.body
    assert_match "Show", @response.body
    assert_match "Raw", @response.body
    assert_match ".json", @response.body
    assert_match "Size", @response.body
    assert_match "Compare", @response.body

    get "/distillator/cache.json", params: {
      term: "heavy",
      http_response_code: "404",
      has_html: "true",
      network_status: "failed",
      health: "network_failed",
      status_group: "4xx",
      content_type: "json",
      hint: "empty_body",
      redirected: "true",
      last_attempt: "last_7d",
      last_success: "last_7d",
      sort: "http_response_code",
      direction: "asc",
      page: "1",
      per_page: "2"
    }

    assert_response :success
    assert_kind_of Array, JSON.parse(@response.body)
    assert_equal "1", @response.headers["X-Page"]
    assert_equal "2", @response.headers["X-Per-Page"]
    assert_equal "3", @response.headers["X-Total-Count"]
    assert_equal "2", @response.headers["X-Total-Pages"]
  end

  private

  def visible_text(html)
    document = Nokogiri::HTML(html)
    document.xpath("//script|//style").remove
    document.text.squish
  end

  def assert_read_only_page_does_not_fetch
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never
  end

  def create_cache(uri: "http://example.org/cached", html: "<html>cached</html>", body: html, name: "Cached", signals: {}, hints: [], final_url: nil, redirect_chain: [], http_response_code: 200, scrape_date: Time.zone.now, successful_refresh: Time.zone.now, updated_at: Time.zone.now)
    cache = Distillator::FetchCache.new(
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
    cache.created_at = updated_at
    cache.updated_at = updated_at
    cache.save!
    cache
  end
end
