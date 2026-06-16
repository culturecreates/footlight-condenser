require "test_helper"

class WringerCompatControllerTest < ActionDispatch::IntegrationTest
  setup do
    Distillator::FetchCache.delete_all
  end

  test "missing uri returns no_content and does not fetch" do
    Distillator::FetchCacheStore.expects(:fetch).never

    get wring_websites_url, params: { format: "json" }

    assert_response :no_content
  end

  test "raw response renders cached html and removes x frame options" do
    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "http://example.org/cached", kwargs[:uri]
      true
    end.returns(cache_like(html: "<html>cached</html>"))

    get wring_websites_url, params: { uri: "http://example.org/cached", format: "raw" }

    assert_response :success
    assert_equal "<html>cached</html>", @response.body
    assert_nil @response.headers["X-Frame-Options"]
  end

  test "raw response returns preserved last known good html after 404" do
    Distillator::FetchCacheStore.expects(:fetch).returns(
      cache_like(
        html: "<html>last good</html>",
        signals: { network_status: "ok", content_type: "html" },
        hints: [],
        final_url: nil,
        redirect_chain: [],
        http_response_code: 404
      )
    )

    get wring_websites_url, params: { uri: "http://example.org/cached", format: "raw", force_scrape: "true" }

    assert_response :success
    assert_equal "<html>last good</html>", @response.body
    assert_nil @response.headers["X-Frame-Options"]
  end

  test "html format redirects to websites path with legacy notice and removes x frame options" do
    Distillator::FetchCacheStore.expects(:fetch).returns(cache_like(html: "<html>cached</html>"))

    get wring_websites_url, params: { uri: "http://example.org/cached", format: "html" }

    assert_redirected_to websites_path
    follow_redirect!
    assert_equal "Website was successfully wrung.", flash[:notice]
  end

  test "html format redirects after forced refresh" do
    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal true, kwargs[:force_scrape]
      true
    end.returns(cache_like(html: "<html>fresh</html>"))

    get wring_websites_url, params: { uri: "http://example.org/cached", format: "html", force_scrape: "true" }

    assert_redirected_to websites_path
    follow_redirect!
    assert_equal "Website was successfully wrung.", flash[:notice]
  end

  test "json response returns exact legacy compatible contract keys and preserves redirect metadata" do
    Distillator::FetchCacheStore.expects(:fetch).returns(cache_like(
      html: "<html>cached</html>",
      signals: {
        network_status: "ok",
        content_type: "html",
        redirect_type: "normal",
        redirected: true,
        final_url: "https://example.org/final"
      },
      hints: ["json_detected"],
      final_url: "https://example.org/final",
      redirect_chain: ["http://example.org/cached", "https://example.org/final"],
      http_response_code: 200
    ))

    get wring_websites_url, params: { uri: "http://example.org/cached", format: "json" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal %w[final_url hints html http_code redirect_chain signals].sort, payload.keys.sort
    assert_equal "<html>cached</html>", payload["html"]
    assert_equal "ok", payload["signals"]["network_status"]
    assert_equal "html", payload["signals"]["content_type"]
    assert_equal "normal", payload["signals"]["redirect_type"]
    assert_equal true, payload["signals"]["redirected"]
    assert_equal "https://example.org/final", payload["signals"]["final_url"]
    assert_equal ["json_detected"], payload["hints"]
    assert_equal "https://example.org/final", payload["final_url"]
    assert_equal ["http://example.org/cached", "https://example.org/final"], payload["redirect_chain"]
    assert_equal 200, payload["http_code"]
    assert_nil @response.headers["X-Frame-Options"]
  end

  test "json response preserves empty redirect chain as array" do
    Distillator::FetchCacheStore.expects(:fetch).returns(cache_like(
      html: "<html>cached</html>",
      signals: { network_status: "ok" },
      hints: [],
      final_url: nil,
      redirect_chain: [],
      http_response_code: 200
    ))

    get wring_websites_url, params: { uri: "http://example.org/cached", format: "json" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal [], payload["redirect_chain"]
    assert_equal [], payload["hints"]
  end

  test "json response returns failure signals and hints without crashing" do
    Distillator::FetchCacheStore.expects(:fetch).returns(cache_like(
      html: "<html>last good</html>",
      signals: { network_status: "failed", timeout: true, content_type: "unknown", redirect_type: "none" },
      hints: ["timeout"],
      final_url: nil,
      redirect_chain: [],
      http_response_code: nil
    ))

    get wring_websites_url, params: { uri: "http://example.org/cached", format: "json", force_scrape: "true" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal %w[final_url hints html http_code redirect_chain signals].sort, payload.keys.sort
    assert_equal "<html>last good</html>", payload["html"]
    assert_equal "failed", payload["signals"]["network_status"]
    assert_equal true, payload["signals"]["timeout"]
    assert_equal "unknown", payload["signals"]["content_type"]
    assert_equal "none", payload["signals"]["redirect_type"]
    assert_equal ["timeout"], payload["hints"]
    assert_nil payload["final_url"]
    assert_equal [], payload["redirect_chain"]
    assert_nil payload["http_code"]
  end

  test "json_post replay preserves POST response contract fields" do
    Distillator::FetchCacheStore.expects(:fetch).returns(cache_like(
      html: '{"result":"ok"}',
      signals: {
        network_status: "ok",
        content_type: "json",
        request_method: "POST",
        redirect_type: "none"
      },
      hints: ["json_detected"],
      final_url: "https://example.org/api",
      redirect_chain: [],
      http_response_code: 200
    ))

    get wring_websites_url, params: { uri: "https://example.org/api", format: "json", json_post: "true" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal %w[final_url hints html http_code redirect_chain signals].sort, payload.keys.sort
    assert_equal '{"result":"ok"}', payload["html"]
    assert_equal "POST", payload["signals"]["request_method"]
    assert_equal "json", payload["signals"]["content_type"]
    assert_equal ["json_detected"], payload["hints"]
    assert_equal "https://example.org/api", payload["final_url"]
    assert_equal [], payload["redirect_chain"]
    assert_equal 200, payload["http_code"]
  end

  test "json_post replay preserves deterministic empty-body failure metadata" do
    Distillator::FetchCacheStore.expects(:fetch).returns(cache_like(
      html: "",
      signals: {
        network_status: "ok",
        content_type: "json",
        request_method: "POST",
        redirect_type: "none",
        empty_body: true
      },
      hints: ["empty_body"],
      final_url: "https://example.org/api",
      redirect_chain: [],
      http_response_code: 200
    ))

    get wring_websites_url, params: { uri: "https://example.org/api", format: "json", json_post: "true", force_scrape: "true" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal "", payload["html"]
    assert_equal true, payload["signals"]["empty_body"]
    assert_equal "POST", payload["signals"]["request_method"]
    assert_equal ["empty_body"], payload["hints"]
    assert_equal 200, payload["http_code"]
  end

  test "json response returns preserved html with failed http code after 404" do
    Distillator::FetchCacheStore.expects(:fetch).returns(cache_like(
      html: "<html>last good</html>",
      signals: { network_status: "ok", content_type: "html" },
      hints: [],
      final_url: nil,
      redirect_chain: [],
      http_response_code: 404
    ))

    get wring_websites_url, params: { uri: "http://example.org/cached", format: "json", force_scrape: "true" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal %w[final_url hints html http_code redirect_chain signals].sort, payload.keys.sort
    assert_equal "<html>last good</html>", payload["html"]
    assert_equal 404, payload["http_code"]
    assert_equal [], payload["hints"]
    assert_equal [], payload["redirect_chain"]
  end

  test "iframe uri returns extracted iframe html in json format" do
    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "http://example.org/iframe", kwargs[:uri]
      assert_equal true, kwargs[:use_phantomjs]
      true
    end.returns(cache_like(
      html: "<html>child iframe</html>",
      signals: { network_status: "ok", content_type: "html" },
      hints: [],
      http_response_code: 200
    ))

    get wring_websites_url, params: { uri: "http://example.org/iframe", format: "json" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal "<html>child iframe</html>", payload["html"]
    assert_equal 200, payload["http_code"]
  end

  test "iframe uri returns extracted iframe html in raw format" do
    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "http://example.org/iframe", kwargs[:uri]
      assert_equal true, kwargs[:use_phantomjs]
      true
    end.returns(cache_like(
      html: "<html>child iframe</html>",
      signals: { network_status: "ok", content_type: "html" },
      hints: [],
      http_response_code: 200
    ))

    get wring_websites_url, params: { uri: "http://example.org/iframe", format: "raw" }

    assert_response :success
    assert_equal "<html>child iframe</html>", @response.body
  end

  test "iframe non 2xx response preserves cached html at controller boundary" do
    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "http://example.org/iframe", kwargs[:uri]
      assert_equal true, kwargs[:use_phantomjs]
      true
    end.returns(cache_like(
      html: "<html>last good iframe</html>",
      signals: { network_status: "ok", content_type: "html" },
      hints: [],
      http_response_code: 404
    ))

    get wring_websites_url, params: { uri: "http://example.org/iframe", format: "json", force_scrape: "true" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal "<html>last good iframe</html>", payload["html"]
    assert_equal 404, payload["http_code"]
  end

  test "wring passes include_fragment to fetch cache store" do
    expect_wring_fetch_param(:include_fragment, true, uri: "http://example.org/page#fragment")

    get wring_websites_url, params: { uri: "http://example.org/page#fragment", format: "json", include_fragment: "true" }

    assert_response :success
  end

  test "wring passes force_scrape to fetch cache store" do
    expect_wring_fetch_param(:force_scrape, true)

    get wring_websites_url, params: { uri: "http://example.org/cached", format: "json", force_scrape: "true" }

    assert_response :success
  end

  test "wring passes force_scrape_every_hrs to fetch cache store" do
    expect_wring_fetch_param(:force_scrape_every_hrs, "24")

    get wring_websites_url, params: { uri: "http://example.org/cached", format: "json", force_scrape_every_hrs: "24" }

    assert_response :success
  end

  test "wring passes absolute_src to fetch cache store" do
    expect_wring_fetch_param(:absolute_src, true)

    get wring_websites_url, params: { uri: "http://example.org/cached", format: "json", absolute_src: "true" }

    assert_response :success
  end

  test "wring passes json_post to fetch cache store" do
    expect_wring_fetch_param(:json_post, true)

    get wring_websites_url, params: { uri: "http://example.org/cached", format: "json", json_post: "true" }

    assert_response :success
  end

  test "wring passes use_phantomjs to fetch cache store" do
    expect_wring_fetch_param(:use_phantomjs, true)

    get wring_websites_url, params: { uri: "http://example.org/cached", format: "json", use_phantomjs: "true" }

    assert_response :success
  end

  test "/websites.json?term finds escaped uri" do
    cache = create_cache(
      html: "<html>cached 404</html>",
      name: "Cached 404",
      json_ld: { "@type" => "Event" },
      http_response_code: 404
    )

    get websites_url(format: :json), params: { term: "http%3A%2F%2Fexample.org%2Fcached" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal 1, payload.size
    record = payload.first
    assert_equal cache.id, record["id"]
    assert_equal "http%3A%2F%2Fexample.org%2Fcached", record["uri"]
    assert_equal "<html>cached 404</html>", record["html"]
    assert_equal "Cached 404", record["name"]
    assert_equal({ "@type" => "Event" }, record["json_ld"])
    assert record["scrape_date"].present?
    assert record["successful_refresh"].present?
    assert_equal 404, record["http_response_code"]
    assert record["created_at"].present?
    assert record["updated_at"].present?
  end

  test "/websites.json?term supports exact legacy URL string" do
    create_cache(http_response_code: 404)

    get "/websites.json?term=http%3A%2F%2Fexample.org%2Fcached"

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal 1, payload.size
    assert_equal "http%3A%2F%2Fexample.org%2Fcached", payload.first["uri"]
    assert_equal 404, payload.first["http_response_code"]
  end

  test "invalid URI returns no_content" do
    get "/websites/wring?uri=http://[invalid&format=json"

    assert_response :no_content
  end

  test "fragment is ignored by default so repeated wrings with different fragments reuse one cache row" do
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::FetchGuard.stubs(:check_response).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::NativeFetch.expects(:call).once.returns(native_fetch_result(body: "<html>cached</html>"))

    get wring_websites_url, params: { uri: "http://example.org/page#one", format: "json" }
    get wring_websites_url, params: { uri: "http://example.org/page#two", format: "json" }

    keys = Distillator::FetchCache.order(:uri_key).pluck(:uri_key)
    assert_equal [CGI.escape("http://example.org/page")], keys
  end

  test "include_fragment true creates separate cache rows for fragment variants" do
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::FetchGuard.stubs(:check_response).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::NativeFetch.expects(:call).twice.returns(native_fetch_result(body: "<html>cached</html>"))

    get wring_websites_url, params: { uri: "http://example.org/page#one", format: "json", include_fragment: "true" }
    get wring_websites_url, params: { uri: "http://example.org/page#two", format: "json", include_fragment: "true" }

    keys = Distillator::FetchCache.order(:uri_key).pluck(:uri_key)
    assert_equal [
      CGI.escape("http://example.org/page#one"),
      CGI.escape("http://example.org/page#two")
    ], keys
  end

  private

  def expect_wring_fetch_param(key, expected_value, uri: "http://example.org/cached")
    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal uri, kwargs[:uri]
      assert_equal expected_value, kwargs[key]
      true
    end.returns(cache_like(html: "<html>cached</html>"))
  end

  def cache_like(
    html: nil,
    signals: {},
    hints: [],
    final_url: nil,
    redirect_chain: [],
    http_response_code: nil
  )
    Struct.new(
      :html,
      :signals,
      :hints,
      :final_url,
      :redirect_chain,
      :http_response_code,
      keyword_init: true
    ).new(
      html: html,
      signals: signals,
      hints: hints,
      final_url: final_url,
      redirect_chain: redirect_chain,
      http_response_code: http_response_code
    )
  end

  def native_fetch_result(body:, status: :ok, http_code: 200, final_url: "http://example.org/page", redirect_chain: [])
    {
      status: status,
      body: body,
      headers: { "content_type" => "text/html" },
      final_url: final_url,
      redirect_chain: redirect_chain,
      wringer: {},
      http_code: http_code,
      raw_body: body
    }
  end

  def create_cache(
    html: "<html>cached</html>",
    name: "cached",
    json_ld: nil,
    signals: {},
    hints: [],
    final_url: nil,
    redirect_chain: [],
    http_response_code: 200
  )
    Distillator::FetchCache.create!(
      uri_key: "http%3A%2F%2Fexample.org%2Fcached",
      normalized_url: "http://example.org/cached",
      html: html,
      body: html,
      name: name,
      json_ld: json_ld,
      scrape_date: Time.zone.now,
      successful_refresh: Time.zone.now,
      http_response_code: http_response_code,
      headers: {},
      signals: signals,
      hints: hints,
      final_url: final_url,
      redirect_chain: redirect_chain
    )
  end
end
