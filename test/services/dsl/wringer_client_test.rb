require "test_helper"

class Dsl::Support::WringerClientTest < ActiveSupport::TestCase
  FakeWringerResponse = Struct.new(:code, :body, :uri, :response, keyword_init: true) do
    def [](key)
      response && (response[key] || response[key.to_s])
    end

    def headers
      response
    end
  end

  FakeHistoryEntry = Struct.new(:uri, keyword_init: true)

  class FakeWringerAgent
    attr_reader :called_urls

    def initialize(response:, history: [])
      @response = response
      @history = history
      @called_urls = []
    end

    def get(url)
      @called_urls << url
      @response
    end

    def history
      @history
    end
  end

  test "successful fetch returns status ok, body string, wringer diagnostics" do
    captured = {}
    agent = mock("agent")
    agent.expects(:get_file).with("wringer://resolved").returns("<html>ok</html>")

    use_wringer = lambda do |url, render_js, scrape_options|
      captured = { url: url, render_js: render_js, scrape_options: scrape_options }
      "wringer://resolved"
    end
    safe_wringer_call = ->(&blk) { blk.call }

    client = Dsl::Support::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: { force_scrape_every_hrs: 2 },
      use_wringer: use_wringer,
      safe_wringer_call: safe_wringer_call,
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal :ok, result[:status]
    assert_equal "<html>ok</html>", result[:body]
    assert result[:wringer].is_a?(Hash)
    assert result[:wringer].key?(:signals)
    assert result[:wringer].key?(:hints)
    assert_equal(
      { url: "https://example.com/events", render_js: false, scrape_options: { force_scrape_every_hrs: 2 } },
      captured
    )
  end

  test "wringer returns signals and hints on successful fetch" do
    agent = mock("agent")
    agent.expects(:get_file).with("wringer://resolved").returns("<html>ok</html>")

    client = Dsl::Support::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal "html", result[:wringer][:signals][:content_type]
    assert_equal "ok", result[:wringer][:signals][:network_status]
    assert_equal [], result[:wringer][:hints]
  end

  test "abort payload returns status abort with original payload preserved" do
    payload = ["abort_update", { error_type: "system_cloudflare", retry: true, cache: false }]
    safe_wringer_call = ->(&_) { payload }

    client = Dsl::Support::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: safe_wringer_call,
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal :abort, result[:status]
    assert_equal payload, result[:body]
    assert_equal "system_cloudflare", result[:wringer][:error_type]
    assert_equal true, result[:wringer][:retry]
    assert_equal false, result[:wringer][:cache]
    assert_equal({}, result[:wringer][:signals])
    assert_equal [], result[:wringer][:hints]
  end

  test "wringer status extracts retry and cache from top-level payload" do
    payload = [
      "abort_update",
      {
        error_type: "system_cloudflare",
        retry: false,
        cache: true,
        policy: { retry: true, cache: false }
      }
    ]

    client = Dsl::Support::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { payload },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal "system_cloudflare", result[:wringer][:error_type]
    assert_equal false, result[:wringer][:retry]
    assert_equal true, result[:wringer][:cache]
    assert_equal({}, result[:wringer][:signals])
    assert_equal [], result[:wringer][:hints]
  end

  test "wringer status falls back to retry and cache from nested policy" do
    payload = [
      "abort_update",
      {
        error_type: "system_queue",
        policy: { retry: true, cache: false }
      }
    ]

    client = Dsl::Support::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { payload },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal "system_queue", result[:wringer][:error_type]
    assert_equal true, result[:wringer][:retry]
    assert_equal false, result[:wringer][:cache]
    assert_equal({}, result[:wringer][:signals])
    assert_equal [], result[:wringer][:hints]
  end

  test "partial abort payload includes only available wringer status fields" do
    payload = ["abort_update", { error_type: "system_cloudflare" }]

    client = Dsl::Support::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { payload },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal "system_cloudflare", result[:wringer][:error_type]
    assert_equal({}, result[:wringer][:signals])
    assert_equal [], result[:wringer][:hints]
  end

  test "render_js option is passed through to use_wringer" do
    captured = {}
    agent = mock("agent")
    agent.expects(:get_file).with("wringer://resolved").returns("<html>ok</html>")

    use_wringer = lambda do |url, render_js, scrape_options|
      captured = { url: url, render_js: render_js, scrape_options: scrape_options }
      "wringer://resolved"
    end

    client = Dsl::Support::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: {},
      use_wringer: use_wringer,
      safe_wringer_call: ->(&blk) { blk.call },
      logger: Rails.logger
    )

    client.fetch(url: "https://example.com/events", render_js: true)

    assert_equal true, captured[:render_js]
  end

  test "custom scrape_options are passed through to use_wringer" do
    captured = {}
    agent = mock("agent")
    agent.expects(:get_file).with("wringer://resolved").returns("<html>ok</html>")

    use_wringer = lambda do |url, render_js, scrape_options|
      captured = { url: url, render_js: render_js, scrape_options: scrape_options }
      "wringer://resolved"
    end

    client = Dsl::Support::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: {},
      use_wringer: use_wringer,
      safe_wringer_call: ->(&blk) { blk.call },
      logger: Rails.logger
    )

    options = { json_post: true, absolute_src: true, force_scrape_every_hrs: 1 }
    client.fetch(url: "https://example.com/events", scrape_options: options)

    assert_equal options, captured[:scrape_options]
  end

  test "nil response remains ok and includes normalized wringer diagnostics" do
    client = Dsl::Support::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { nil },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")
    assert_equal :ok, result[:status]
    assert_nil result[:body]
    assert_equal({}, result[:wringer][:signals])
    assert_equal [], result[:wringer][:hints]
  end

  test "malformed abort payload is normalized to explicit wringer abort error" do
    malformed_payload = ["abort_update", "broken-payload"]
    malformed_client = Dsl::Support::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { malformed_payload },
      logger: Rails.logger
    )

    malformed = malformed_client.fetch(url: "https://example.com/events")
    assert_equal :abort, malformed[:status]
    assert_equal "abort_update", malformed[:body].first
    assert_equal "WringerMalformedControlPayload", malformed[:body].last[:error_type]
    assert_equal "wringer", malformed[:body].last[:source]
    assert_equal({}, malformed[:wringer][:signals])
    assert_equal [], malformed[:wringer][:hints]
  end

  test "skip control action is normalized to abort_update wringer skip" do
    client = Dsl::Support::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { ["skip", { reason: "policy_skip" }] },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal :abort, result[:status]
    assert_equal "abort_update", result[:body].first
    assert_equal "WringerSkip", result[:body].last[:error_type]
    assert_equal "wringer", result[:body].last[:source]
  end

  test "unknown wringer control action is normalized to unsupported action abort_update" do
    client = Dsl::Support::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { ["foo", { reason: "unknown" }] },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal :abort, result[:status]
    assert_equal "abort_update", result[:body].first
    assert_equal "WringerUnsupportedAction", result[:body].last[:error_type]
    assert_equal "Unsupported Wringer action: foo", result[:body].last[:error]
    assert_equal "wringer", result[:body].last[:source]
  end

  test "single-element arrays are not treated as control tuples" do
    payload = ["skip"]
    client = Dsl::Support::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { payload },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal :ok, result[:status]
    assert_equal payload, result[:body]
  end

  test "fetch failure is normalized to WringerFetchError with url step" do
    client = Dsl::Support::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { ["abort_update", { error: "connection refused", error_type: "wringer_unreachable", source: "wringer" }] },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal :abort, result[:status]
    assert_equal "abort_update", result[:body].first
    assert_equal "WringerFetchError", result[:body].last[:error_type]
    assert_equal "url", result[:body].last[:step]
    assert_equal "wringer", result[:body].last[:source]
  end

  test "metadata normalization enforces signals hash and hints array for abort payload" do
    payload = ["abort_update", { error_type: "system_cloudflare", signals: "bad-shape", hints: "bad-shape" }]
    client = Dsl::Support::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { payload },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal :abort, result[:status]
    assert_equal({}, result[:wringer][:signals])
    assert_equal [], result[:wringer][:hints]
  end

  test "control tuples never return html body content" do
    agent = mock("agent")
    agent.expects(:get_file).with("wringer://resolved").returns("<html>should_not_escape_control</html>")

    client = Dsl::Support::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: lambda do |&blk|
        blk.call
        ["skip", { reason: "policy_skip" }]
      end,
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal :abort, result[:status]
    assert_equal "abort_update", result[:body].first
    refute_equal "<html>should_not_escape_control</html>", result[:body]
  end

  test "fetch detects 404 from response metadata and exposes wringer status" do
    agent = mock("agent")
    helper = ApplicationController.helpers
    helper.stubs(:wringer_rules).returns(
      {
        "http_404" => {
          "match" => { "http_code" => 404 },
          "policy" => { "action" => "abort_update", "retry" => false, "cache" => false, "error_code" => "http_404" }
        }
      }.to_a
    )
    response = Struct.new(:code, :body, :uri).new(
      404,
      "Not Found",
      URI("https://example.com/missing")
    )
    agent.expects(:get).with("wringer://resolved").returns(response)

    client = Dsl::Support::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: helper.method(:safe_wringer_call),
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal :abort, result[:status]
    assert_equal "abort_update", result[:body].first
    assert_equal "http_404", result[:wringer][:error_type]
  end

  test "fetch detects 500 from response metadata and exposes wringer status" do
    agent = mock("agent")
    helper = ApplicationController.helpers
    helper.stubs(:wringer_rules).returns(
      {
        "http_5xx" => {
          "match" => { "http_code" => [500, 502, 503, 504] },
          "policy" => { "action" => "abort_update", "retry" => true, "cache" => false, "error_code" => "http_server_error" }
        }
      }.to_a
    )
    response = Struct.new(:code, :body, :uri).new(
      500,
      "Internal Server Error",
      URI("https://example.com/error")
    )
    agent.expects(:get).with("wringer://resolved").returns(response)

    client = Dsl::Support::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: helper.method(:safe_wringer_call),
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal :abort, result[:status]
    assert_equal "abort_update", result[:body].first
    assert_equal "http_server_error", result[:wringer][:error_type]
  end

  test "fetch captures final_url for redirect responses" do
    agent = mock("agent")
    helper = ApplicationController.helpers
    helper.stubs(:wringer_rules).returns(
      {
        "redirect_to_listing" => {
          "match" => { "final_url_patterns" => ["/events$"] },
          "policy" => { "action" => "abort_update", "retry" => false, "cache" => false, "error_code" => "redirect_to_listing" }
        }
      }.to_a
    )
    response = Struct.new(:code, :body, :uri).new(
      200,
      "<html>listing page</html>",
      URI("https://example.com/events")
    )
    agent.expects(:get).with("wringer://resolved").returns(response)

    client = Dsl::Support::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: helper.method(:safe_wringer_call),
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal :abort, result[:status]
    assert_equal "redirect_to_listing", result[:wringer][:error_type]
    assert_equal "https://example.com/events", result[:wringer][:final_url]
  end

  test "canonical wringer contract marks received_404 from metadata" do
    agent = mock("agent")
    helper = ApplicationController.helpers
    helper.stubs(:wringer_rules).returns(
      {
        "http_404" => {
          "match" => { "http_code" => 404 },
          "policy" => { "action" => "abort_update", "retry" => false, "cache" => false, "error_code" => "http_404" }
        }
      }.to_a
    )
    response = Struct.new(:code, :body, :uri).new(404, "Not Found", URI("https://example.com/missing"))
    agent.expects(:get).with("wringer://resolved").returns(response)

    client = Dsl::Support::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: helper.method(:safe_wringer_call),
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal true, result[:wringer][:received_404]
    assert_equal false, result[:wringer][:unreachable]
    assert_equal false, result[:wringer][:system_error]
    assert_equal "abort_update", result[:wringer][:policy_action]
  end

  test "canonical wringer contract marks system_error from metadata" do
    agent = mock("agent")
    helper = ApplicationController.helpers
    helper.stubs(:wringer_rules).returns(
      {
        "http_5xx" => {
          "match" => { "http_code" => [500, 502, 503, 504] },
          "policy" => { "action" => "abort_update", "retry" => true, "cache" => false, "error_code" => "http_server_error" }
        }
      }.to_a
    )
    response = Struct.new(:code, :body, :uri).new(500, "Internal Server Error", URI("https://example.com/error"))
    agent.expects(:get).with("wringer://resolved").returns(response)

    client = Dsl::Support::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: helper.method(:safe_wringer_call),
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal false, result[:wringer][:received_404]
    assert_equal false, result[:wringer][:unreachable]
    assert_equal true, result[:wringer][:system_error]
    assert_equal "abort_update", result[:wringer][:policy_action]
  end

  test "canonical wringer contract marks unreachable on network abort payload" do
    payload = [
      "abort_update",
      {
        error_type: "wringer_unreachable",
        policy: { action: "abort_update", retry: true, cache: false }
      }
    ]

    client = Dsl::Support::WringerClient.new(
      agent: mock("agent"),
      render_js: false,
      scrape_options: {},
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&_) { payload },
      logger: Rails.logger
    )

    result = client.fetch(url: "https://example.com/events")

    assert_equal true, result[:wringer][:unreachable]
    assert_equal false, result[:wringer][:received_404]
    assert_equal false, result[:wringer][:system_error]
    assert_equal "abort_update", result[:wringer][:policy_action]
  end

  test "matches Distillator fetch normalization for wringer response shapes" do
    cases = [
      {
        name: "successful string response",
        response: -> { "<html>ok</html>" },
        safe_wringer_call: passthrough_safe_wringer_call
      },
      {
        name: "Mechanize-like response with headers and final_url",
        response: lambda {
          FakeWringerResponse.new(
            code: 200,
            body: "<html>ok</html>",
            uri: URI("https://example.com/final"),
            response: { "Content-Type" => "text/html" }
          )
        },
        safe_wringer_call: passthrough_safe_wringer_call
      },
      {
        name: "abort_update response",
        response: -> { "<html>unused</html>" },
        safe_wringer_call: control_safe_wringer_call(
          ["abort_update", { error_type: "system_cloudflare", retry: true, cache: false }]
        )
      },
      {
        name: "404 response",
        response: lambda {
          FakeWringerResponse.new(
            code: 404,
            body: "Not Found",
            uri: URI("https://example.com/missing"),
            response: { "Content-Type" => "text/html" }
          )
        },
        safe_wringer_call: response_policy_safe_wringer_call(
          http_code: 404,
          error_type: "http_404",
          retry_value: false
        )
      },
      {
        name: "500 response",
        response: lambda {
          FakeWringerResponse.new(
            code: 500,
            body: "Internal Server Error",
            uri: URI("https://example.com/error"),
            response: { "Content-Type" => "text/html" }
          )
        },
        safe_wringer_call: response_policy_safe_wringer_call(
          http_code: 500,
          error_type: "http_server_error",
          retry_value: true
        )
      },
      {
        name: "malformed control payload",
        response: -> { "<html>unused</html>" },
        safe_wringer_call: control_safe_wringer_call(["abort_update", "broken-payload"])
      },
      {
        name: "unsupported control action",
        response: -> { "<html>unused</html>" },
        safe_wringer_call: control_safe_wringer_call(["foo", { reason: "unknown" }])
      },
      {
        name: "redirect_chain extraction",
        response: lambda {
          FakeWringerResponse.new(
            code: 200,
            body: "<html>redirected</html>",
            uri: URI("https://example.com/final"),
            response: { "Content-Type" => "text/html" }
          )
        },
        history: [
          FakeHistoryEntry.new(uri: URI("https://example.com/start")),
          FakeHistoryEntry.new(uri: URI("https://example.com/final"))
        ],
        safe_wringer_call: passthrough_safe_wringer_call
      }
    ]

    cases.each do |example|
      dsl_agent = FakeWringerAgent.new(
        response: example[:response].call,
        history: example[:history] || []
      )
      distillator_agent = FakeWringerAgent.new(
        response: example[:response].call,
        history: example[:history] || []
      )

      dsl_result = wringer_client(
        agent: dsl_agent,
        safe_wringer_call: example[:safe_wringer_call]
      ).fetch(url: "https://example.com/events")
      distillator_result = Distillator::FetchService.fetch_wringer_backed(
        url: "https://example.com/events",
        render_js: false,
        scrape_options: {},
        agent: distillator_agent,
        use_wringer: wringer_url_resolver,
        safe_wringer_call: example[:safe_wringer_call],
        logger: Rails.logger
      )

      assert_equal distillator_result, dsl_result, example[:name]
    end
  end

  private

  def wringer_client(agent:, safe_wringer_call:)
    Dsl::Support::WringerClient.new(
      agent: agent,
      render_js: false,
      scrape_options: {},
      use_wringer: wringer_url_resolver,
      safe_wringer_call: safe_wringer_call,
      logger: Rails.logger
    )
  end

  def wringer_url_resolver
    ->(*_) { "wringer://resolved" }
  end

  def passthrough_safe_wringer_call
    lambda do |normalize_response: false, &blk|
      blk.call
    end
  end

  def control_safe_wringer_call(payload)
    lambda do |normalize_response: false, &blk|
      payload
    end
  end

  def response_policy_safe_wringer_call(http_code:, error_type:, retry_value:)
    lambda do |normalize_response: false, &blk|
      response = blk.call
      return response unless response.respond_to?(:code) && response.code.to_i == http_code

      [
        "abort_update",
        {
          error_type: error_type,
          policy: { action: "abort_update", retry: retry_value, cache: false }
        }
      ]
    end
  end
end
