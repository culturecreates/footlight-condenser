require "test_helper"

class WringerContractDistillatorTest < ActionDispatch::IntegrationTest
  setup do
    Distillator::FetchCache.delete_all
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::FetchGuard.stubs(:check_response).returns(Distillator::FetchGuard::Result.new(allowed: true))
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
  end

  test "raw response creates a cache row and returns stored html" do
    Distillator::NativeFetch.expects(:call).once.returns(
      native_fetch_result(
        body: "<html><title>First</title>ok</html>",
        final_url: "https://example.org/final"
      )
    )

    get wring_websites_url, params: { uri: "http://example.org/wring-raw", format: "raw", force_scrape: "false" }

    assert_response :success
    assert_equal "<html><title>First</title>ok</html>", @response.body

    cache = Distillator::FetchCache.find_by!(uri_key: CGI.escape("http://example.org/wring-raw"))
    assert_equal "<html><title>First</title>ok</html>", cache.html
    assert_equal "<html><title>First</title>ok</html>", cache.body
    assert_equal "First", cache.name
    assert_equal 200, cache.http_response_code
  end

  test "html response redirects with wringer-compatible notice" do
    Distillator::NativeFetch.expects(:call).once.returns(native_fetch_result(body: "<html>ok</html>"))

    get wring_websites_url, params: { uri: "http://example.org/wring-html", format: "html" }

    assert_redirected_to websites_path
    follow_redirect!
    assert_equal "Website was successfully wrung.", flash[:notice]
  end

  test "json response returns stored metadata from the real cache row" do
    Distillator::NativeFetch.expects(:call).once.returns(
      native_fetch_result(
        body: '{"result":"ok"}',
        headers: { "content_type" => "application/json" },
        final_url: "https://example.org/wring-post/final",
        redirect_chain: ["http://example.org/wring-post", "https://example.org/wring-post/final"],
        signals: { network_status: "ok", content_type: "json", redirect_type: "normal" },
        hints: ["json_detected"]
      )
    )

    get wring_websites_url, params: { uri: "http://example.org/wring-post", format: "json", json_post: "true" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal %w[final_url hints html http_code redirect_chain signals].sort, payload.keys.sort
    assert_equal "json", payload.dig("signals", "content_type")
    assert_equal ["json_detected"], payload["hints"]
    assert_equal "https://example.org/wring-post/final", payload["final_url"]
    assert_equal ["http://example.org/wring-post", "https://example.org/wring-post/final"], payload["redirect_chain"]
    assert_equal 200, payload["http_code"]

    cache = Distillator::FetchCache.find_by!(uri_key: CGI.escape("http://example.org/wring-post"))
    assert_equal "json", cache.signals["content_type"]
    assert_equal ["json_detected"], cache.hints
    assert_equal "https://example.org/wring-post/final", cache.final_url
    assert_equal ["http://example.org/wring-post", "https://example.org/wring-post/final"], cache.redirect_chain
  end

  test "second call without force uses the cache and does not fetch again" do
    Distillator::NativeFetch.expects(:call).once.returns(native_fetch_result(body: "<html>cached once</html>"))

    2.times do
      get wring_websites_url, params: { uri: "http://example.org/cached-once", format: "raw" }
      assert_response :success
      assert_equal "<html>cached once</html>", @response.body
    end

    assert_equal 1, Distillator::FetchCache.where(uri_key: CGI.escape("http://example.org/cached-once")).count
  end

  test "force_scrape true performs a new fetch and updates cache metadata" do
    Distillator::NativeFetch.expects(:call).twice.returns(
      native_fetch_result(body: "<html><title>Old</title>old</html>"),
      native_fetch_result(body: "<html><title>New</title>new</html>", final_url: "https://example.org/forced")
    )

    get wring_websites_url, params: { uri: "http://example.org/forced", format: "raw" }
    get wring_websites_url, params: { uri: "http://example.org/forced", format: "json", force_scrape: "true" }

    payload = JSON.parse(@response.body)
    cache = Distillator::FetchCache.find_by!(uri_key: CGI.escape("http://example.org/forced"))

    assert_equal "<html><title>New</title>new</html>", payload["html"]
    assert_equal "<html><title>New</title>new</html>", cache.html
    assert_equal "New", cache.name
    assert_equal "https://example.org/forced", cache.final_url
  end

  test "force_scrape_every_hrs zero performs a new fetch" do
    Distillator::NativeFetch.expects(:call).twice.returns(
      native_fetch_result(body: "<html>before zero</html>"),
      native_fetch_result(body: "<html>after zero</html>")
    )

    get wring_websites_url, params: { uri: "http://example.org/zero-threshold", format: "raw" }
    get wring_websites_url, params: { uri: "http://example.org/zero-threshold", format: "raw", force_scrape_every_hrs: "0" }

    assert_response :success
    assert_equal "<html>after zero</html>", @response.body
  end

  test "force_scrape_every_hrs large value uses fresh cache" do
    Distillator::NativeFetch.expects(:call).once.returns(native_fetch_result(body: "<html>fresh cache</html>"))

    get wring_websites_url, params: { uri: "http://example.org/fresh-cache", format: "raw" }
    get wring_websites_url, params: { uri: "http://example.org/fresh-cache", format: "raw", force_scrape_every_hrs: "999999" }

    assert_response :success
    assert_equal "<html>fresh cache</html>", @response.body
  end

  test "use_phantomjs true routes through phantomjs fetcher and caches rendered html" do
    Distillator::PhantomjsFetcher.expects(:call).once.returns(
      phantomjs_fetch_result(body: "<html>rendered by phantom</html>")
    )

    get wring_websites_url, params: { uri: "http://example.org/rendered", format: "raw", use_phantomjs: "true" }

    assert_response :success
    assert_equal "<html>rendered by phantom</html>", @response.body

    cache = Distillator::FetchCache.find_by!(uri_key: CGI.escape("http://example.org/rendered"))
    assert_equal "<html>rendered by phantom</html>", cache.html
    assert_equal "legacy_phantomjs", cache.signals["renderer"]
    assert_equal "phantomjs", cache.signals["fetch_backend"]
    assert_equal true, cache.signals["use_phantomjs"]
  end

  test "iframe url forces phantomjs even when use_phantomjs is false" do
    Distillator::PhantomjsFetcher.expects(:call).with do |kwargs|
      assert_equal true, kwargs[:iframe]
      true
    end.returns(
      phantomjs_fetch_result(body: "<html>iframe child</html>", iframe: true)
    )

    get wring_websites_url, params: { uri: "http://example.org/eventiframe", format: "json", use_phantomjs: "false" }

    assert_response :success
    payload = JSON.parse(@response.body)
    assert_equal "<html>iframe child</html>", payload["html"]
    assert_equal true, payload.dig("signals", "phantomjs_iframe_extraction")
  end

  test "invalid uri returns no_content" do
    Distillator::NativeFetch.expects(:call).never

    get wring_websites_url, params: { uri: "http://[invalid", format: "json" }

    assert_response :no_content
  end

  test "include_fragment false excludes the fragment from the cache key" do
    Distillator::NativeFetch.expects(:call).once.returns(native_fetch_result(body: "<html>fragmentless</html>"))

    get wring_websites_url, params: { uri: "http://example.org/page#one", format: "raw", include_fragment: "false" }
    get wring_websites_url, params: { uri: "http://example.org/page#two", format: "raw", include_fragment: "false" }

    assert_equal [CGI.escape("http://example.org/page")], Distillator::FetchCache.order(:uri_key).pluck(:uri_key)
  end

  test "include_fragment true keeps the fragment in the cache key" do
    Distillator::NativeFetch.expects(:call).twice.returns(native_fetch_result(body: "<html>fragmentful</html>"))

    get wring_websites_url, params: { uri: "http://example.org/page#one", format: "raw", include_fragment: "true" }
    get wring_websites_url, params: { uri: "http://example.org/page#two", format: "raw", include_fragment: "true" }

    assert_equal(
      [CGI.escape("http://example.org/page#one"), CGI.escape("http://example.org/page#two")],
      Distillator::FetchCache.order(:uri_key).pluck(:uri_key)
    )
  end

  test "wringer url-key contract exact cases match legacy outputs" do
    assert_equal "http%3A%2F%2Fculturecreates.com%2F", Distillator::WringerUrlKey.call("http://culturecreates.com/").uri_key
    assert_equal "https%3A%2F%2Fculturecreates.com%2Fpeople", Distillator::WringerUrlKey.call("https://culturecreates.com/people#gregory").uri_key
    assert_equal "https%3A%2F%2Fculturecreates.com%2Fpeople%23gregory", Distillator::WringerUrlKey.call("https://culturecreates.com/people#gregory", include_fragment: true).uri_key
    assert_equal "http%3A%2F%2Fculturecreates.com%2Fpeople%2F", Distillator::WringerUrlKey.call("culturecreates.com/people/").uri_key
  end

  test "wring route stores cache using the exact wringer-compatible key" do
    Distillator::NativeFetch.expects(:call).once.returns(native_fetch_result(body: "<html>contract key</html>"))

    get wring_websites_url, params: { uri: "culturecreates.com/people/", format: "raw" }

    assert_response :success
    assert_equal ["http%3A%2F%2Fculturecreates.com%2Fpeople%2F"], Distillator::FetchCache.order(:uri_key).pluck(:uri_key)
  end

  private

  def native_fetch_result(body:, headers: { "content_type" => "text/html" }, final_url: nil, redirect_chain: nil, signals: {}, hints: [])
    normalized_final_url = final_url || "http://example.org/final"
    {
      status: :ok,
      body: body,
      headers: headers,
      final_url: normalized_final_url,
      redirect_chain: redirect_chain || [normalized_final_url],
      wringer: { signals: signals, hints: hints },
      http_code: 200,
      raw_body: body
    }
  end

  def phantomjs_fetch_result(body:, iframe: false)
    {
      status: :ok,
      body: body,
      headers: { "content_type" => "text/html" },
      final_url: "http://example.org/rendered",
      redirect_chain: ["http://example.org/rendered"],
      wringer: {
        signals: {
          network_status: "ok",
          content_type: "html",
          renderer: "legacy_phantomjs",
          fetch_backend: "phantomjs",
          request_method: "GET",
          use_phantomjs: true,
          phantomjs_iframe_extraction: iframe
        },
        hints: ["legacy_phantomjs"]
      },
      http_code: 200,
      raw_body: body,
      fetch_path: "native"
    }
  end
end
