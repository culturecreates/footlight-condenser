require "test_helper"

class Distillator::PhantomjsFetcherTest < ActiveSupport::TestCase
  setup do
    @old_phantomjs_api_key = ENV["PHANTOMJS_API_KEY"]
    @old_direct_fallback = ENV["DISTILLATOR_ALLOW_RENDERED_DIRECT_FALLBACK"]
  end

  teardown do
    ENV["PHANTOMJS_API_KEY"] = @old_phantomjs_api_key
    ENV["DISTILLATOR_ALLOW_RENDERED_DIRECT_FALLBACK"] = @old_direct_fallback
  end

  test "uses the renderer key for transport and validates the redacted redirect URL" do
    key = "test-phantomjs-key"
    ENV["PHANTOMJS_API_KEY"] = key
    target = "https://example.com/rendered-event"
    request_url = Distillator::PhantomjsFetcher.request_url(url: target, iframe: false)
    response_url = "https://phantomjscloud.com/api/browser/v2/#{key}/?request=fixture"
    page = "<html>Rendered event</html>"
    response = Struct.new(:code, :body, :uri, :response).new(
      200, page, URI(response_url), { "Content-Type" => "text/html", "X-Request-Echo" => key }
    )
    agent = mock("renderer transport")
    agent.expects(:get).with(request_url).returns(response)
    agent.stubs(:history).returns([Struct.new(:uri).new(URI(response_url))])
    Resolv.stubs(:getaddresses).with("example.com").returns(["93.184.216.34"])
    Resolv.expects(:getaddresses).with("phantomjscloud.com").at_least_once.returns(["8.8.8.8"])
    logs = StringIO.new
    logger = Logger.new(logs)

    result = Distillator::FetchService.fetch_result(url: target, mode: :internal, render_js: true, agent: agent, logger: logger)

    assert_equal :ok, result[:status]
    assert_equal page, result[:body]
    assert_equal page, result[:raw_body]
    assert_equal target, result[:final_url]
    assert_equal [response_url.sub(key, "%5BFILTERED%5D")], result[:redirect_chain]
    assert_includes logs.string, "distillator.native_fetch.request"
    assert_includes logs.string, "distillator.native_fetch.response"
    assert_includes logs.string, "/api/browser/v2/%5BFILTERED%5D/"
    refute_includes logs.string, key
    refute_includes result.inspect, key
    assert_equal "[FILTERED]", result.dig(:headers, :x_request_echo)
  end

  test "renderer request preserves the exact filtered calendar URL" do
    ENV["PHANTOMJS_API_KEY"] = "fake-filtered-key"
    urls = [
      "https://www.chasse-galerie.ca/fr/calendrier?page=2&number_items=48&categ=concert",
      "https://ccat.qc.ca/vitrine/calendrier-culturel/?pag=3&typeevenement%5B%5D=389&typeevenement%5B%5D=252&mrc=&du=2022-08-01",
      "https://www.ovation.ca/00000P/fr/Search/AllEvents/?pageNumber=2",
      "https://example.com/events?category=theatre%20jeunesse&category=musique&date=2026-11-27"
    ]

    urls.each do |url|
      renderer_url = Distillator::PhantomjsFetcher.request_url(url: url, iframe: false)
      params = URI.decode_www_form(URI.parse(renderer_url).query).to_h
      assert_equal ["request"], params.keys, "renderer must not split off calendar filters"
      payload = JSON.parse(params.fetch("request"))
      assert_equal url, payload.fetch("url")
      assert_equal "html", payload.fetch("renderType")
      assert_equal false, payload.fetch("outputAsJson")
      assert_equal({ "ignoreImages" => true, "waitInterval" => 2500 }, payload.fetch("requestSettings"))
    end

    iframe_url = Distillator::PhantomjsFetcher.request_url(url: urls.first, iframe: true)
    assert_equal true, JSON.parse(URI.decode_www_form(URI.parse(iframe_url).query).to_h.fetch("request")).fetch("outputAsJson")
  end

  test "active rendered fetch sends preserved filters through PhantomJSCloud transport" do
    ENV["PHANTOMJS_API_KEY"] = "fake-filtered-key"
    target = "https://ccat.qc.ca/vitrine/calendrier-culturel/?pag=2&typeevenement%5B%5D=389&typeevenement%5B%5D=252&mrc="
    expected = Distillator::PhantomjsFetcher.request_url(url: target, iframe: false)
    rendered_html = '<html><body><a href="/spectacle/1">Spectacle</a></body></html>'
    response = Struct.new(:code, :body, :uri, :response).new(
      200, rendered_html, URI(expected), { "Content-Type" => "text/html" }
    )
    agent = mock("filtered renderer transport")
    agent.expects(:get).with(expected).returns(response)
    agent.stubs(:history).returns([])
    Resolv.stubs(:getaddresses).with("ccat.qc.ca").returns(["93.184.216.34"])
    Resolv.stubs(:getaddresses).with("phantomjscloud.com").returns(["8.8.8.8"])

    result = Distillator::FetchService.fetch_result(url: target, mode: :internal, render_js: true,
      agent: agent, logger: Logger.new(StringIO.new))
    assert_equal :ok, result[:status]
    assert_equal rendered_html, result[:body]
    assert_equal "legacy_phantomjs", result.dig(:wringer, :signals, :renderer)
    assert_equal "phantomjs", result.dig(:wringer, :signals, :fetch_backend)
    assert_equal target, result[:final_url]
  end

  test "redacts renderer network failures before they enter downstream evidence" do
    key = "test-phantomjs-key"
    ENV["PHANTOMJS_API_KEY"] = key
    target = "https://example.com/rendered-event"
    request_url = Distillator::PhantomjsFetcher.request_url(url: target, iframe: false)
    agent = mock("renderer transport")
    agent.expects(:get).with(request_url).raises(Net::ReadTimeout, "Request timed out for #{request_url}")
    logs = StringIO.new

    result = Distillator::PhantomjsFetcher.call(url: target, uri_key: target, iframe: false, agent: agent, logger: Logger.new(logs))

    assert_equal :abort, result[:status]
    assert_includes result[:body].last[:error], "/api/browser/v2/%5BFILTERED%5D/"
    refute_includes result.inspect, key
    refute_includes logs.string, key
  end

  test "redacts unexpected renderer URL exceptions before they are raised" do
    key = "test-phantomjs-key"
    ENV["PHANTOMJS_API_KEY"] = key
    target = "https://example.com/rendered-event"
    request_url = Distillator::PhantomjsFetcher.request_url(url: target, iframe: false)
    agent = mock("renderer transport")
    agent.expects(:get).with(request_url).raises(URI::InvalidURIError, "Invalid URI #{request_url}")

    error = assert_raises(URI::InvalidURIError) do
      Distillator::PhantomjsFetcher.call(url: target, uri_key: target, iframe: false, agent: agent)
    end

    assert_includes error.message, "/api/browser/v2/%5BFILTERED%5D/"
    refute_includes error.full_message, key
    assert_nil error.cause
  end

  test "missing phantomjs api key returns renderer unavailable even with the old direct fallback enabled" do
    ENV["PHANTOMJS_API_KEY"] = nil
    ENV["DISTILLATOR_ALLOW_RENDERED_DIRECT_FALLBACK"] = "true"
    Distillator::NativeFetch.expects(:call).never

    result = Distillator::PhantomjsFetcher.call(
      url: "https://www.ovation.ca/event",
      uri_key: CGI.escape("https://www.ovation.ca/event"),
      iframe: false
    )

    assert_equal :abort, result[:status]
    assert_equal true, result.dig(:wringer, :signals, :renderer_unavailable)
    assert_equal "none", result.dig(:wringer, :signals, :renderer_fallback)
    assert_includes result.dig(:wringer, :hints), "phantomjs_unavailable"
  end
end
