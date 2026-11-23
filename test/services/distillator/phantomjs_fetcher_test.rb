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

  test "uses the renderer key for transport and redacts it from logs and fetch metadata" do
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
    logs = StringIO.new
    logger = Logger.new(logs)

    result = Distillator::PhantomjsFetcher.call(url: target, uri_key: target, iframe: false, agent: agent, logger: logger)

    assert_equal :ok, result[:status]
    assert_equal page, result[:body]
    assert_equal page, result[:raw_body]
    assert_equal target, result[:final_url]
    assert_includes logs.string, "distillator.native_fetch.request"
    assert_includes logs.string, "distillator.native_fetch.response"
    assert_includes logs.string, "[FILTERED]"
    refute_includes logs.string, key
    refute_includes result.inspect, key
    assert_equal "[FILTERED]", result.dig(:headers, :x_request_echo)
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
    assert_includes result[:body].last[:error], "[FILTERED]"
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

    assert_includes error.message, "[FILTERED]"
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
