require "test_helper"

class Distillator::NativeFetchTest < ActiveSupport::TestCase
  class CapturingLogger
    attr_reader :infos

    def initialize
      @infos = []
    end

    def info(payload)
      @infos << payload
    end
  end

  ConfigurableAgent = Struct.new(:response, :history, :user_agent_alias) do
    def get(_url)
      response
    end
  end

  test "call does not use Wringer helpers and fetches the original URL" do
    ApplicationController.expects(:helpers).never

    response = Struct.new(:code, :body, :uri, :response).new(
      200,
      "<html>native</html>",
      URI("https://example.com/final"),
      { "Content-Type" => "text/html" }
    )
    history_entry = Struct.new(:uri).new(URI("https://example.com/final"))
    agent = ConfigurableAgent.new(response, [history_entry], nil)

    result = Distillator::NativeFetch.call(
      url: "https://example.com/events",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :ok, result[:status]
    assert_equal "<html>native</html>", result[:body]
    assert_equal({ content_type: "text/html" }, result[:headers])
    assert_equal "https://example.com/final", result[:final_url]
    assert_equal ["https://example.com/final"], result[:redirect_chain]
    assert_equal "Mac Safari", agent.user_agent_alias
    assert_equal "native", result.dig(:wringer, :signals, :fetch_backend)
    assert_equal "GET", result.dig(:wringer, :signals, :request_method)
    assert_equal false, result.dig(:wringer, :signals, :use_phantomjs)
    assert_kind_of Hash, result[:wringer]
  end

  test "call logs native fetch request and normalized response" do
    logger = CapturingLogger.new
    response = Struct.new(:code, :body, :uri, :response).new(
      200,
      "<html>native</html>",
      URI("https://example.com/final"),
      { "Content-Type" => "text/html" }
    )
    history_entry = Struct.new(:uri).new(URI("https://example.com/final"))
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/events").returns(response)
    agent.stubs(:history).returns([history_entry])

    Distillator::NativeFetch.call(
      url: "https://example.com/events",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: logger
    )

    assert_equal(
      {
        event: "distillator.native_fetch.request",
        url: "https://example.com/events",
        render_js: false,
        json_post: false
      },
      logger.infos.first
    )
    assert_equal "distillator.native_fetch.response", logger.infos.second[:event]
    assert_equal :ok, logger.infos.second[:status]
    assert_equal 200, logger.infos.second[:http_code]
    assert_equal "https://example.com/final", logger.infos.second[:final_url]
    assert_equal ["https://example.com/final"], logger.infos.second[:redirect_chain]
    assert_equal({ content_type: "text/html" }, logger.infos.second[:headers])
  end

  test "call retries once with ssl verify none when supported" do
    response = Struct.new(:code, :body, :uri, :response).new(
      200,
      "<html>ssl fallback</html>",
      URI("https://example.com/ssl"),
      { "Content-Type" => "text/html" }
    )
    history_entry = Struct.new(:uri).new(URI("https://example.com/ssl"))
    http = Struct.new(:verify_mode).new(nil)
    mechanize_wrapper = Struct.new(:http).new(http)
    agent = mock("agent")
    agent.stubs(:public_methods).returns([])
    agent.stubs(:agent).returns(mechanize_wrapper)
    calls = 0
    agent.stubs(:get).with("https://example.com/ssl") do
      calls += 1
      raise OpenSSL::SSL::SSLError, "certificate verify failed" if calls == 1

      response
    end
    agent.stubs(:history).returns([history_entry])

    result = Distillator::NativeFetch.call(
      url: "https://example.com/ssl",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :ok, result[:status]
    assert_equal OpenSSL::SSL::VERIFY_NONE, http.verify_mode
    assert_equal true, result.dig(:wringer, :signals, :ssl_verify_none_fallback)
    assert_includes result.dig(:wringer, :hints), "ssl_verify_none_fallback"
  end

  test "call uses post with default json content type when json_post is true" do
    response = Struct.new(:code, :body, :uri, :response).new(
      200,
      '{"ok":true}',
      URI("https://example.com/api"),
      { "Content-Type" => "application/json" }
    )
    history_entry = Struct.new(:uri).new(URI("https://example.com/api"))
    agent = mock("agent")
    agent.expects(:post).with("https://example.com/api", "", { "Content-Type" => "application/json" }).returns(response)
    agent.stubs(:history).returns([history_entry])

    result = Distillator::NativeFetch.call(
      url: "https://example.com/api",
      render_js: false,
      scrape_options: { json_post: true },
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :ok, result[:status]
    assert_equal '{"ok":true}', result[:body]
    assert_equal "json", result.dig(:wringer, :signals, :content_type)
    assert_equal "POST", result.dig(:wringer, :signals, :request_method)
    assert_equal "native", result.dig(:wringer, :signals, :fetch_backend)
    assert_includes result.dig(:wringer, :hints), "json_detected"
  end

  test "call does not use post when json_post is string false" do
    response = Struct.new(:code, :body, :uri, :response).new(
      200,
      "<html>get</html>",
      URI("https://example.com/api"),
      { "Content-Type" => "text/html" }
    )
    history_entry = Struct.new(:uri).new(URI("https://example.com/api"))
    agent = mock("agent")
    agent.expects(:post).never
    agent.expects(:get).with("https://example.com/api").returns(response)
    agent.stubs(:history).returns([history_entry])

    result = Distillator::NativeFetch.call(
      url: "https://example.com/api",
      render_js: false,
      scrape_options: { json_post: "false" },
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :ok, result[:status]
    assert_equal "<html>get</html>", result[:body]
  end

  test "call preserves explicit content type header for json_post" do
    response = Struct.new(:code, :body, :uri, :response).new(
      200,
      '{"ok":true}',
      URI("https://example.com/api"),
      { "Content-Type" => "application/json" }
    )
    history_entry = Struct.new(:uri).new(URI("https://example.com/api"))
    agent = mock("agent")
    agent.expects(:post).with("https://example.com/api", "", { "Content-Type" => "application/custom+json" }).returns(response)
    agent.stubs(:history).returns([history_entry])

    Distillator::NativeFetch.call(
      url: "https://example.com/api",
      render_js: false,
      scrape_options: { json_post: true, headers: { "Content-Type" => "application/custom+json" } },
      agent: agent,
      logger: Rails.logger
    )
  end

  test "call preserves redirect chain and final_url across redirects" do
    response = Struct.new(:code, :body, :uri, :response).new(
      200,
      "<html>redirected</html>",
      URI("https://example.com/final"),
      { "Content-Type" => "text/html" }
    )
    history = [
      Struct.new(:uri).new(URI("https://example.com/start")),
      Struct.new(:uri).new(URI("https://example.com/final"))
    ]
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/start").returns(response)
    agent.stubs(:history).returns(history)

    result = Distillator::NativeFetch.call(
      url: "https://example.com/start",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal "https://example.com/final", result[:final_url]
    assert_equal ["https://example.com/start", "https://example.com/final"], result[:redirect_chain]
    assert_equal "normal", result.dig(:wringer, :signals, :redirect_type)
    assert_equal true, result.dig(:wringer, :signals, :redirected)
    assert_equal "https://example.com/final", result.dig(:wringer, :signals, :final_url)
  end

  test "call records generic error match metadata for policy rejected html" do
    response = Struct.new(:code, :body, :uri, :response).new(
      200,
      "<html><body><h1>Une erreur est survenue</h1><p>Retry later.</p></body></html>",
      URI("https://example.com/final"),
      { "Content-Type" => "text/html" }
    )
    history_entry = Struct.new(:uri).new(URI("https://example.com/final"))
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/failure").returns(response)
    agent.stubs(:history).returns([history_entry])

    result = Distillator::NativeFetch.call(
      url: "https://example.com/failure",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal "generic_error_text", result.dig(:wringer, :signals, :primary_issue_key)
    assert_equal "body_text", result.dig(:wringer, :signals, :primary_issue_match, "source")
    assert_equal "Une erreur est survenue", result.dig(:wringer, :signals, :primary_issue_match, "pattern")
  end

  test "call marks json responses with json_detected metadata" do
    response = Struct.new(:code, :body, :uri, :response).new(
      200,
      '{"ok":true}',
      URI("https://example.com/api"),
      { "Content-Type" => "application/json" }
    )
    history_entry = Struct.new(:uri).new(URI("https://example.com/api"))
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/api").returns(response)
    agent.stubs(:history).returns([history_entry])

    result = Distillator::NativeFetch.call(
      url: "https://example.com/api",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal "json", result.dig(:wringer, :signals, :content_type)
    assert_equal true, result.dig(:wringer, :signals, :json_detected)
    assert_includes result.dig(:wringer, :hints), "json_detected"
  end

  test "call marks empty body responses with empty_body hint" do
    response = Struct.new(:code, :body, :uri, :response).new(
      200,
      "",
      URI("https://example.com/empty"),
      { "Content-Type" => "text/html" }
    )
    history_entry = Struct.new(:uri).new(URI("https://example.com/empty"))
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/empty").returns(response)
    agent.stubs(:history).returns([history_entry])

    result = Distillator::NativeFetch.call(
      url: "https://example.com/empty",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_includes result.dig(:wringer, :hints), "empty_body"
  end

  test "call returns abort contract for 404 response" do
    missing_page = Struct.new(:code, :body, :uri, :response).new(
      404,
      "Not Found",
      URI("https://example.com/missing"),
      { "Content-Type" => "text/html" }
    )
    error = Mechanize::ResponseCodeError.new(missing_page, "404")
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/missing").raises(error)
    agent.stubs(:history).returns([])

    result = Distillator::NativeFetch.call(
      url: "https://example.com/missing",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :abort, result[:status]
    assert_equal "abort_update", result[:body].first
    assert_equal "http_404", result.dig(:wringer, :error_type)
    assert_equal "https://example.com/missing", result[:final_url]
    assert_equal({ content_type: "text/html" }, result[:headers])
  end

  test "call returns abort contract for json_post 404 response" do
    missing_page = Struct.new(:code, :body, :uri, :response).new(
      404,
      '{"error":"missing"}',
      URI("https://example.com/api"),
      { "Content-Type" => "application/json" }
    )
    error = Mechanize::ResponseCodeError.new(missing_page, "404")
    agent = mock("agent")
    agent.expects(:post).with("https://example.com/api", "", { "Content-Type" => "application/json" }).raises(error)
    agent.stubs(:history).returns([])

    result = Distillator::NativeFetch.call(
      url: "https://example.com/api",
      render_js: false,
      scrape_options: { json_post: true },
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :abort, result[:status]
    assert_equal '{"error":"missing"}', result[:raw_body]
    assert_equal "http_404", result.dig(:wringer, :error_type)
  end

  test "call normalizes abort_update control payloads to abort responses" do
    payload = ["abort_update", { error_type: "system_cloudflare", retry: true, cache: false, source: "wringer" }]
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/control").returns(payload)
    agent.stubs(:history).returns([])

    result = Distillator::NativeFetch.call(
      url: "https://example.com/control",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :abort, result[:status]
    assert_equal payload, result[:body]
    assert_nil result[:http_code]
    assert_nil result[:raw_body]
    assert_equal "system_cloudflare", result.dig(:wringer, :error_type)
    assert_equal true, result.dig(:wringer, :retry)
    assert_equal false, result.dig(:wringer, :cache)
  end

  test "call normalizes skip control action into abort contract" do
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/skip").returns(["skip", { reason: "duplicate" }])
    agent.stubs(:history).returns([])

    result = Distillator::NativeFetch.call(
      url: "https://example.com/skip",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :abort, result[:status]
    assert_equal "abort_update", result[:body].first
    assert_equal "WringerSkip", result.dig(:wringer, :error_type)
  end

  test "call normalizes malformed control payloads into abort contract" do
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/malformed").returns(["abort_update", "broken-payload"])
    agent.stubs(:history).returns([])

    result = Distillator::NativeFetch.call(
      url: "https://example.com/malformed",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :abort, result[:status]
    assert_equal "abort_update", result[:body].first
    assert_equal "WringerMalformedControlPayload", result.dig(:wringer, :error_type)
  end

  test "call normalizes unsupported control actions into abort contract" do
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/unsupported").returns(["pause", { reason: "unknown" }])
    agent.stubs(:history).returns([])

    result = Distillator::NativeFetch.call(
      url: "https://example.com/unsupported",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :abort, result[:status]
    assert_equal "abort_update", result[:body].first
    assert_equal "WringerUnsupportedAction", result.dig(:wringer, :error_type)
  end

  test "call returns abort contract for 500 response" do
    error_page = Struct.new(:code, :body, :uri, :response).new(
      500,
      "Internal Server Error",
      URI("https://example.com/error"),
      { "Content-Type" => "text/html" }
    )
    error = Mechanize::ResponseCodeError.new(error_page, "500")
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/error").raises(error)
    agent.stubs(:history).returns([])

    result = Distillator::NativeFetch.call(
      url: "https://example.com/error",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :abort, result[:status]
    assert_equal "http_server_error", result.dig(:wringer, :error_type)
    assert_equal true, result.dig(:wringer, :system_error)
  end

  test "call returns abort contract for timeout" do
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/slow").raises(Net::ReadTimeout, "timeout")

    result = Distillator::NativeFetch.call(
      url: "https://example.com/slow",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :abort, result[:status]
    assert_equal "NativeFetchError", result.dig(:wringer, :error_type)
    assert_equal "failed", result.dig(:wringer, :signals, :network_status)
    assert_includes result.dig(:wringer, :hints), "timeout"
  end

  test "call returns abort contract for json_post timeout" do
    agent = mock("agent")
    agent.expects(:post).with("https://example.com/slow", "", { "Content-Type" => "application/json" }).raises(Net::ReadTimeout, "timeout")

    result = Distillator::NativeFetch.call(
      url: "https://example.com/slow",
      render_js: false,
      scrape_options: { json_post: true },
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :abort, result[:status]
    assert_equal "failed", result.dig(:wringer, :signals, :network_status)
    assert_includes result.dig(:wringer, :hints), "timeout"
  end

  test "call returns abort contract for ssl error" do
    agent = mock("agent")
    agent.stubs(:agent).returns(nil)
    agent.expects(:get).with("https://example.com/ssl").raises(OpenSSL::SSL::SSLError, "certificate verify failed")

    result = Distillator::NativeFetch.call(
      url: "https://example.com/ssl",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :abort, result[:status]
    assert_equal "NativeFetchError", result.dig(:wringer, :error_type)
    assert_equal "failed", result.dig(:wringer, :signals, :network_status)
  end

  test "call returns abort contract for socket error" do
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/down").raises(SocketError, "getaddrinfo")

    result = Distillator::NativeFetch.call(
      url: "https://example.com/down",
      render_js: false,
      scrape_options: {},
      agent: agent,
      logger: Rails.logger
    )

    assert_equal :abort, result[:status]
    assert_equal "NativeFetchError", result.dig(:wringer, :error_type)
    assert_equal "failed", result.dig(:wringer, :signals, :network_status)
  end
end
