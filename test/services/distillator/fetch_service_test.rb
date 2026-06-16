require "test_helper"

class Distillator::FetchServiceTest < ActiveSupport::TestCase
  class CapturingLogger
    attr_reader :infos, :warnings

    def initialize
      @infos = []
      @warnings = []
    end

    def info(payload)
      @infos << payload
    end

    def warn(payload)
      @warnings << payload
    end
  end

  setup do
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    @old_replay_fetch = ENV["REPLAY_FETCH"]
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
    ENV["REPLAY_FETCH"] = @old_replay_fetch
  end

  test "fetch defaults to legacy fetch without website context" do
    ENV["DISTILLATOR_FETCH_MODE"] = nil
    Distillator::FetchService.expects(:internal_fetch).never
    Distillator::FetchService.expects(:legacy_fetch).with do |kwargs|
      assert_equal "https://example.com/events", kwargs[:url]
      assert_equal false, kwargs[:render_js]
      assert_equal({}, kwargs[:scrape_options])
      true
    end.returns(
      status: :ok,
      body: "<html>ok</html>",
      headers: { content_type: "text/html" },
      final_url: "https://example.com/events",
      redirect_chain: ["https://example.com/events"],
      wringer: { signals: {}, hints: [] }
    )

    result = Distillator::FetchService.fetch(url: "https://example.com/events")

    assert_equal :ok, result[:status]
    assert_equal "<html>ok</html>", result[:body]
    assert_equal(
      [:body, :duration_ms, :final_url, :headers, :redirect_chain, :status, :wringer],
      result.keys.sort
    )
  end

  test "explicit active alias mode uses the native path when eligible" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new
    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    Distillator::FetchService.expects(:internal_fetch).with do |kwargs|
      assert_equal "https://example.com/events", kwargs[:url]
      assert_equal false, kwargs[:render_js]
      assert_equal({}, kwargs[:scrape_options])
      true
    end.returns(
      status: :ok,
      body: "<html>internal</html>",
      headers: { content_type: "text/html" },
      final_url: "https://example.com/events",
      redirect_chain: [],
      wringer: { signals: {}, hints: [] }
    )
    Distillator::FetchService.expects(:legacy_fetch).never

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call },
      logger: logger
    )

    assert_equal :ok, result[:status]
    assert_equal "<html>internal</html>", result[:body]
    assert_equal(
      {
        event: "distillator.fetch.eligibility",
        eligible: true,
        url: "https://example.com/events",
        render_js: false,
        json_post: false,
        reason: :native_http_get,
        policy: :native,
        mode_source: "explicit",
        forced_legacy: false,
        scheme: "https",
        statement_id: nil,
        source_id: nil,
        webpage_id: nil,
        website_id: nil
      },
      logger.infos.first
    )
    assert_equal(
      {
        event: "distillator.fetch.path",
        path: "native_fetch",
        url: "https://example.com/events",
        mode_source: "explicit",
        statement_id: nil,
        source_id: nil,
        webpage_id: nil,
        website_id: nil
      },
      logger.infos.second
    )
    assert_equal "fetch.native", logger.infos.last[:event]
    assert_equal "https%3A%2F%2Fexample.com%2Fevents", logger.infos.last[:uri_key]
    assert_equal "active", logger.infos.last[:mode]
    assert_equal "explicit", logger.infos.last[:mode_source]
    assert_equal "native", logger.infos.last[:fetch_path]
    assert_nil logger.infos.last[:website_id]
    assert_equal "html", result.dig(:wringer, :signals, :content_type)
    assert_equal "none", result.dig(:wringer, :signals, :redirect_type)
  end

  test "internal fetch enriches redirect metadata for wringer-compatible result shape" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    Distillator::FetchService.expects(:internal_fetch).returns(
      status: :ok,
      body: "<html>redirected</html>",
      headers: { content_type: "text/html" },
      final_url: "https://example.com/final",
      redirect_chain: ["https://example.com/start", "https://example.com/final"],
      wringer: { signals: { network_status: "ok" }, hints: [] }
    )

    result = Distillator::FetchService.fetch(
      url: "https://example.com/start",
      mode: :internal,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call }
    )

    assert_equal "normal", result.dig(:wringer, :signals, :redirect_type)
    assert_equal true, result.dig(:wringer, :signals, :redirected)
    assert_equal "https://example.com/final", result.dig(:wringer, :signals, :final_url)
  end

  test "explicit internal mode uses rendered fetch when render_js is true" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new
    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    Distillator::FetchService.expects(:internal_fetch).with do |kwargs|
      assert_equal true, kwargs[:render_js]
      true
    end.returns(
      status: :ok,
      body: "<html>rendered</html>",
      headers: { content_type: "text/html" },
      final_url: "https://example.com/rendered",
      redirect_chain: ["https://example.com/events", "https://example.com/rendered"],
      wringer: { signals: { network_status: "ok", renderer: "legacy_phantomjs" }, hints: ["legacy_phantomjs"] },
      http_code: 200
    )
    Distillator::FetchService.expects(:legacy_fetch).never

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal,
      render_js: true,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call },
      logger: logger
    )

    assert_equal "<html>rendered</html>", result[:body]
    assert_equal :rendered_fetch, logger.infos.first[:reason]
    assert_equal "legacy_phantomjs", result.dig(:wringer, :signals, :renderer)
    assert_equal "https://example.com/rendered", result[:final_url]
    assert_equal ["https://example.com/events", "https://example.com/rendered"], result[:redirect_chain]
  end

  test "explicit internal mode uses native fetch for json_post" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new
    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    Distillator::FetchService.expects(:internal_fetch).with do |kwargs|
      assert_equal true, kwargs[:scrape_options][:json_post]
      true
    end.returns(
      status: :ok,
      body: "{\"ok\":true}",
      headers: { content_type: "application/json" },
      final_url: "https://example.com/events",
      redirect_chain: ["https://example.com/events"],
      wringer: { signals: { content_type: "json" }, hints: ["json_detected"] }
    )
    Distillator::FetchService.expects(:legacy_fetch).never

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal,
      scrape_options: { json_post: true },
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call },
      logger: logger
    )

    assert_equal "{\"ok\":true}", result[:body]
    assert_equal :native_http_post, logger.infos.first[:reason]
    assert_equal "json", result.dig(:wringer, :signals, :content_type)
    assert_equal "fetch.native", logger.infos.last[:event]
  end

  test "internal fetch classifies queue it body through yaml issue metadata" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    Distillator::FetchService.expects(:internal_fetch).returns(
      status: :ok,
      body: "<html>Queue-it Please wait while we redirect you</html>",
      raw_body: "<html>Queue-it Please wait while we redirect you</html>",
      headers: { content_type: "text/html" },
      final_url: "https://example.com/events",
      redirect_chain: [],
      wringer: { signals: { network_status: "ok" }, hints: [] },
      http_code: 200
    )

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call }
    )

    assert_equal "queue_it", result.dig(:wringer, :signals, :primary_issue_key)
    assert_equal "system_queue", result.dig(:wringer, :signals, :primary_issue_error_code)
    assert_equal "warning", result.dig(:wringer, :signals, :primary_issue_severity)
    assert_equal "anti_bot", result.dig(:wringer, :signals, :primary_issue_category)
    assert_includes result.dig(:wringer, :hints), "queue_it"
    assert_equal "abort_update", result.dig(:wringer, :policy_action)
  end

  test "rendered redirect to listing keeps transport success but marks content failure" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    Distillator::FetchService.expects(:internal_fetch).returns(
      status: :ok,
      body: "<html><title>Recherche par titre</title></html>",
      raw_body: "<html><title>Recherche par titre</title></html>",
      headers: { content_type: "text/html" },
      final_url: "https://www.ovation.ca/Search/Title/",
      redirect_chain: ["https://www.ovation.ca/event", "https://www.ovation.ca/Search/Title/"],
      wringer: {
        signals: {
          network_status: "ok",
          renderer: "legacy_phantomjs",
          primary_issue_key: "redirect_to_listing",
          primary_issue_severity: "failed",
          blocking_issue_key: "redirect_to_listing"
        },
        hints: ["legacy_phantomjs", "redirect_to_listing"],
        policy_action: "abort_update"
      },
      http_code: 200
    )

    result = Distillator::FetchService.fetch(
      url: "https://www.ovation.ca/event",
      mode: :internal,
      render_js: true
    )

    assert_equal true, result.dig(:wringer, :signals, :transport_success)
    assert_equal false, result.dig(:wringer, :signals, :content_success)
    assert_equal "redirect_to_listing", result.dig(:wringer, :signals, :blocking_issue_key)
    assert_equal "abort_update", result.dig(:wringer, :policy_action)
  end

  test "non 2xx fetch remains transport and content failure" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    Distillator::FetchService.expects(:internal_fetch).returns(
      status: :abort,
      body: ["abort_update", { error_type: "http_server_error" }],
      raw_body: "<html><title>Server Error</title></html>",
      headers: { content_type: "text/html" },
      final_url: "https://example.com/events",
      redirect_chain: [],
      wringer: {
        signals: {
          network_status: "ok",
          primary_issue_key: "http_5xx",
          blocking_issue_key: "http_5xx"
        },
        hints: ["http_server_error"]
      },
      http_code: 500
    )

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal
    )

    assert_equal false, result.dig(:wringer, :signals, :transport_success)
    assert_equal false, result.dig(:wringer, :signals, :content_success)
    assert_equal "http_5xx", result.dig(:wringer, :signals, :blocking_issue_key)
  end

  test "explicit internal mode aborts for unsupported scheme before any network call" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new
    Distillator::FetchService.expects(:internal_fetch).never
    Distillator::FetchService.expects(:legacy_fetch).never

    result = Distillator::FetchService.fetch(
      url: "ftp://example.com/events",
      mode: :internal,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call },
      logger: logger
    )

    assert_equal :abort, result[:status]
    assert_equal :unsupported_scheme, logger.infos.first[:reason]
    assert_equal "unsupported_scheme", result.dig(:wringer, :signals, :native_ineligible_reason)
  end

  test "explicit internal mode falls back to legacy for forced legacy option" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new
    Distillator::FetchService.expects(:internal_fetch).never
    Distillator::FetchService.expects(:legacy_fetch).returns(
      status: :ok,
      body: "<html>legacy</html>",
      wringer: { signals: {}, hints: [] }
    )

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal,
      scrape_options: { force_legacy: true },
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call },
      logger: logger
    )

    assert_equal "<html>legacy</html>", result[:body]
    assert_equal :forced_legacy, logger.infos.first[:reason]
  end

  test "ineligible log includes machine readable fields" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new
    Distillator::FetchService.expects(:internal_fetch).never
    Distillator::FetchService.expects(:legacy_fetch).returns(
      status: :ok,
      body: "<html>legacy</html>",
      wringer: { signals: {}, hints: [] }
    )

    Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal,
      scrape_options: { force_legacy: true, json_post: true },
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call },
      logger: logger
    )

    assert_equal "distillator.fetch_mode.internal_ineligible", logger.infos.first[:event]
    assert_equal "https://example.com/events", logger.infos.first[:url]
    assert_equal false, logger.infos.first[:render_js]
    assert_equal true, logger.infos.first[:json_post]
    assert_equal :forced_legacy, logger.infos.first[:reason]
    assert_equal :explicit_legacy_fallback, logger.infos.first[:policy]
    assert_equal "explicit", logger.infos.first[:mode_source]
    assert_equal "distillator.fetch.legacy_fallback", logger.warnings.first[:event]
    assert_equal true, logger.warnings.first[:deprecated]
    assert_equal "explicit", logger.warnings.first[:mode_source]
  end

  test "shadow mode skips comparison when native candidate is forced legacy" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new
    Distillator::FetchService.expects(:internal_fetch).never
    Distillator::FetchShadowComparator.expects(:compare).never
    Distillator::FetchService.expects(:legacy_fetch).returns(
      status: :ok,
      body: "<html>legacy</html>",
      wringer: { signals: {}, hints: [] }
    )

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :shadow,
      scrape_options: { json_post: true, force_legacy: true },
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call },
      logger: logger
    )

    assert_equal "<html>legacy</html>", result[:body]
    assert_equal :forced_legacy, logger.infos.first[:reason]
    assert_equal "distillator.fetch_shadow.skipped", logger.infos.second[:event]
    assert_equal :forced_legacy, logger.infos.second[:reason]
    assert_equal "forced_legacy", result.dig(:wringer, :signals, :native_ineligible_reason)
  end

  test "shadow mode aborts blocked url before any network call and records skipped comparison" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new
    Distillator::FetchService.expects(:legacy_fetch).never
    Distillator::FetchService.expects(:internal_fetch).never
    Distillator::FetchShadowComparator.expects(:compare).never

    result = Distillator::FetchService.fetch(
      url: "http://127.0.0.1/events",
      mode: :shadow,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call },
      logger: logger
    )

    assert_equal :abort, result[:status]
    assert_equal :blocked_url, logger.infos.first[:reason]
    assert_equal "distillator.fetch_shadow.skipped", logger.infos.second[:event]
    assert_equal :blocked_url, logger.infos.second[:reason]
  end

  test "shadow mode returns legacy result and compares internal result" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new
    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    legacy = {
      status: :ok,
      body: "<html>legacy</html>",
      headers: {},
      final_url: nil,
      redirect_chain: [],
      wringer: { signals: {}, hints: [] }
    }
    internal = legacy.merge(body: "<html>internal</html>")

    Distillator::FetchService.expects(:legacy_fetch).returns(legacy)
    Distillator::FetchService.expects(:internal_fetch).returns(internal)
    Distillator::FetchShadowComparator.expects(:compare).with do |kwargs|
      assert_equal legacy, kwargs[:legacy]
      assert_equal internal, kwargs[:internal]
      true
    end

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :shadow,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call },
      logger: logger,
      log_context: { statement_id: 11, source_id: 22, webpage_id: 33, website_id: 44 }
    )

    assert_equal "<html>legacy</html>", result[:body]
    assert_equal "fetch.shadow_compare", logger.infos.last[:event]
    assert_equal "explicit", logger.infos.last[:mode_source]
    assert_equal "https%3A%2F%2Fexample.com%2Fevents", logger.infos.last[:uri_key]
    assert_equal 11, logger.infos.last[:statement_id]
    assert_equal 22, logger.infos.last[:source_id]
    assert_equal 33, logger.infos.last[:webpage_id]
    assert_equal 44, logger.infos.last[:website_id]
  end

  test "shadow mode swallows internal errors and returns legacy result" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    legacy = {
      status: :ok,
      body: "<html>legacy</html>",
      headers: {},
      final_url: nil,
      redirect_chain: [],
      wringer: { signals: {}, hints: [] }
    }

    Distillator::FetchService.expects(:legacy_fetch).returns(legacy)
    Distillator::FetchService.expects(:internal_fetch).raises(StandardError, "internal boom")

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :shadow,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call }
    )

    assert_equal "<html>legacy</html>", result[:body]
  end

  test "internal mode returns abort for blocked URL" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new
    Distillator::FetchService.expects(:internal_fetch).never
    Distillator::FetchService.expects(:legacy_fetch).never

    result = Distillator::FetchService.fetch(
      url: "http://127.0.0.1/events",
      mode: :internal,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call },
      logger: logger
    )

    assert_equal :abort, result[:status]
    assert_equal "abort_update", result[:body].first
    assert_equal "DistillatorFetchBlocked", result[:body].last[:error_type]
    assert_equal "distillator_fetch_guard", result[:body].last[:source]
    assert_equal false, result[:body].last[:retry]
    assert_equal false, result[:body].last[:cache]
    assert_equal "url", result[:body].last[:step]
    assert_equal "blocked_url", result[:body].last[:signals][:native_ineligible_reason]
    assert_equal "blocked_private_ip", result[:body].last[:signals][:guard_reason]
    assert_equal({}, result[:headers])
    assert_equal "http://127.0.0.1/events", result[:final_url]
    assert_equal [], result[:redirect_chain]
    assert_equal "DistillatorFetchBlocked", result.dig(:wringer, :error_type)
    assert_equal "distillator_fetch_guard", result.dig(:wringer, :source)
    assert_equal "blocked_url", result.dig(:wringer, :signals, :native_ineligible_reason)
    assert_equal "blocked_private_ip", result.dig(:wringer, :signals, :guard_reason)
    assert_equal "blocked", result.dig(:wringer, :signals, :network_status)
    assert_includes result.dig(:wringer, :hints), "blocked_url"
    assert_includes result.dig(:wringer, :hints), "blocked_private_ip"
    assert_includes result.dig(:wringer, :hints), "blocked"
    assert_equal "fetch.abort", logger.infos.last[:event]
  end

  test "shadow mode does not call legacy fetch when url is blocked" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchService.expects(:legacy_fetch).never
    Distillator::FetchService.expects(:internal_fetch).never
    Distillator::FetchShadowComparator.expects(:compare).never

    result = Distillator::FetchService.fetch(
      url: "http://127.0.0.1/events",
      mode: :shadow,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call }
    )

    assert_equal :abort, result[:status]
  end

  test "replay mode bypasses fetch mode selection" do
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    ENV["REPLAY_FETCH"] = "true"
    Distillator::FetchGuard.expects(:check_url).never
    Distillator::FetchReplay.expects(:load).with(url: "https://example.com/events").returns(
      status: :ok,
      body: "<html>replay</html>",
      headers: {},
      final_url: nil,
      redirect_chain: [],
      wringer: {},
      duration_ms: 0
    )
    Distillator::FetchService.expects(:internal_fetch).never
    Distillator::FetchService.expects(:legacy_fetch).never

    result = Distillator::FetchService.fetch(url: "https://example.com/events")

    assert_equal "<html>replay</html>", result[:body]
  end

  test "returns body and wringer metadata on success" do
    client = mock("wringer_client")
    client.expects(:fetch).with(url: "https://example.com/events").returns(
      status: :ok,
      body: "<html>ok</html>",
      headers: { content_type: "text/html" },
      final_url: "https://example.com/final",
      redirect_chain: ["https://example.com/start", "https://example.com/final"],
      wringer: { signals: { network_status: "ok" }, hints: [] }
    )

    Dsl::Support::WringerClient.expects(:new).with do |ctx|
      assert_instance_of Mechanize, ctx[:agent]
      assert_equal false, ctx[:render_js]
      assert_equal({ force_legacy: true }, ctx[:scrape_options])
      assert_equal :use_wringer, ctx[:use_wringer].name
      assert_equal :safe_wringer_call, ctx[:safe_wringer_call].name
      assert_equal Rails.logger, ctx[:logger]
      true
    end.returns(client)

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal,
      scrape_options: { force_legacy: true }
    )

    assert_equal :ok, result[:status]
    assert_equal "<html>ok</html>", result[:body]
    assert_equal({ content_type: "text/html" }, result[:headers])
    assert_equal "https://example.com/final", result[:final_url]
    assert_equal ["https://example.com/start", "https://example.com/final"], result[:redirect_chain]
    assert_equal "ok", result.dig(:wringer, :signals, :network_status)
    assert_equal "html", result.dig(:wringer, :signals, :content_type)
    assert_equal "normal", result.dig(:wringer, :signals, :redirect_type)
    assert_equal true, result.dig(:wringer, :signals, :redirected)
    assert_equal "https://example.com/final", result.dig(:wringer, :signals, :final_url)
    assert_equal ["forced_legacy"], result.dig(:wringer, :hints)
  end

  test "returns abort_update payload unchanged on failure" do
    payload = ["abort_update", { error_type: "system_cloudflare", retry: true, cache: false }]
    client = mock("wringer_client")
    client.expects(:fetch).with(url: "https://example.com/events").returns(
      status: :abort,
      body: payload,
      wringer: { error_type: "system_cloudflare", retry: true, cache: false, signals: {}, hints: [] }
    )

    Dsl::Support::WringerClient.stubs(:new).returns(client)

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal,
      scrape_options: { force_legacy: true }
    )

    assert_equal :abort, result[:status]
    assert_equal payload, result[:body]
  end

  test "preserves wringer signals and hints" do
    wringer = {
      error_type: "system_queue",
      retry: true,
      cache: false,
      signals: { network_status: "failed", content_type: "html" },
      hints: ["timeout", "empty_body"]
    }
    client = mock("wringer_client")
    client.expects(:fetch).with(url: "https://example.com/events").returns(
      status: :abort,
      body: ["abort_update", { error_type: "system_queue" }],
      wringer: wringer
    )

    Dsl::Support::WringerClient.stubs(:new).returns(client)

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal,
      scrape_options: { force_legacy: true }
    )

    assert_equal "failed", result.dig(:wringer, :signals, :network_status)
    assert_equal "html", result.dig(:wringer, :signals, :content_type)
    assert_equal "none", result.dig(:wringer, :signals, :redirect_type)
    assert_equal false, result.dig(:wringer, :signals, :redirected)
    assert_equal wringer[:hints] + ["forced_legacy"], result.dig(:wringer, :hints)
  end

  test "includes duration_ms" do
    client = mock("wringer_client")
    client.expects(:fetch).with(url: "https://example.com/events").returns(
      status: :ok,
      body: "<html>ok</html>",
      wringer: { signals: {}, hints: [] }
    )

    Dsl::Support::WringerClient.stubs(:new).returns(client)

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal,
      scrape_options: { force_legacy: true }
    )

    assert result.key?(:duration_ms)
    assert_kind_of Numeric, result[:duration_ms]
    assert_operator result[:duration_ms], :>=, 0
  end

  test "records fetch response passively without changing returned value" do
    Distillator::FetchService.expects(:internal_fetch).never
    Distillator::FetchService.expects(:legacy_fetch).returns(
      status: :ok,
      body: "<html>ok</html>",
      wringer: { signals: {}, hints: [] }
    )
    Distillator::FetchRecorder.expects(:record).with do |kwargs|
      assert_equal "https://example.com/events", kwargs[:url]
      assert_equal :ok, kwargs[:response][:status]
      assert_equal "<html>ok</html>", kwargs[:response][:body]
      assert_equal({}, kwargs[:response][:headers])
      assert_nil kwargs[:response][:final_url]
      assert_equal [], kwargs[:response][:redirect_chain]
      assert_equal "ok", kwargs[:response].dig(:wringer, :signals, :network_status)
      assert_equal "html", kwargs[:response].dig(:wringer, :signals, :content_type)
      assert_equal "none", kwargs[:response].dig(:wringer, :signals, :redirect_type)
      assert_equal false, kwargs[:response].dig(:wringer, :signals, :redirected)
      assert_equal ["forced_legacy"], kwargs[:response].dig(:wringer, :hints)
      assert_kind_of Numeric, kwargs[:response][:duration_ms]
      true
    end

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal,
      scrape_options: { force_legacy: true }
    )

    assert_equal :ok, result[:status]
    assert_equal "<html>ok</html>", result[:body]
    assert_equal({}, result[:headers])
    assert_nil result[:final_url]
    assert_equal [], result[:redirect_chain]
    assert_equal "ok", result.dig(:wringer, :signals, :network_status)
    assert_equal "html", result.dig(:wringer, :signals, :content_type)
    assert_equal "none", result.dig(:wringer, :signals, :redirect_type)
    assert_equal false, result.dig(:wringer, :signals, :redirected)
    assert_equal ["forced_legacy"], result.dig(:wringer, :hints)
    assert_kind_of Numeric, result[:duration_ms]
  end

  test "internal_fetch exposes response metadata" do
    response = Struct.new(:code, :body, :uri, :response).new(
      200,
      "<html>ok</html>",
      URI("https://example.com/final"),
      { "Content-Type" => "text/html" }
    )
    history_entry = Struct.new(:uri).new(URI("https://example.com/final"))
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/events").returns(response)
    agent.stubs(:history).returns([history_entry])

    result = Distillator::FetchService.send(
      :internal_fetch,
      url: "https://example.com/events",
      render_js: false,
      scrape_options: {},
      agent: agent
    )

    assert_equal({ content_type: "text/html" }, result[:headers])
    assert_equal "https://example.com/final", result[:final_url]
    assert_equal ["https://example.com/final"], result[:redirect_chain]
  end

  test "internal mode ignores Wringer helper callbacks when using NativeFetch" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    ApplicationController.expects(:helpers).never

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

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal,
      agent: agent,
      use_wringer: ->(*_) { flunk "use_wringer should not be called by NativeFetch" },
      safe_wringer_call: ->(*_) { flunk "safe_wringer_call should not be called by NativeFetch" }
    )

    assert_equal :ok, result[:status]
    assert_equal "<html>native</html>", result[:body]
    assert_equal({ content_type: "text/html" }, result[:headers])
    assert_equal "https://example.com/final", result[:final_url]
    assert_equal ["https://example.com/final"], result[:redirect_chain]
  end

  test "internal mode remains separate from FetchCacheStore because websites wring owns cache compatibility" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    Distillator::FetchCacheStore.expects(:fetch).never

    response = Struct.new(:code, :body, :uri, :response).new(
      200,
      "<html>internal</html>",
      URI("https://example.com/events"),
      { "Content-Type" => "text/html" }
    )
    agent = mock("agent")
    agent.expects(:get).with("https://example.com/events").returns(response)
    agent.stubs(:history).returns([])

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :internal,
      agent: agent,
      use_wringer: ->(*_) { flunk "use_wringer should not be called by NativeFetch" },
      safe_wringer_call: ->(*_) { flunk "safe_wringer_call should not be called by NativeFetch" }
    )

    assert_equal :ok, result[:status]
    assert_equal "<html>internal</html>", result[:body]
    assert_equal(
      [:body, :duration_ms, :final_url, :headers, :redirect_chain, :status, :wringer],
      result.keys.sort
    )
  end

  test "active website uses the native condenser path even when global mode is legacy" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new
    website = websites(:one)
    website.update!(distillator_mode: "active")

    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    Distillator::FetchService.expects(:internal_fetch).returns(
      status: :ok,
      body: "<html>internal</html>",
      headers: { content_type: "text/html" },
      final_url: "https://example.com/events",
      redirect_chain: [],
      wringer: { signals: {}, hints: [] }
    )
    Distillator::FetchService.expects(:legacy_fetch).never

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      website: website,
      log_context: { website_id: website.id },
      logger: logger
    )

    assert_equal "<html>internal</html>", result[:body]
    assert_equal "active", logger.infos.last[:mode]
    assert_equal "website", logger.infos.last[:mode_source]
    assert_equal website.id, logger.infos.first[:website_id]
    assert_equal website.id, logger.infos.second[:website_id]
    assert_equal website.id, logger.infos.last[:website_id]
  end

  test "shadow website returns legacy result and records Distillator comparison" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new
    website = websites(:one)
    website.update!(distillator_mode: "shadow")

    Distillator::FetchGuard.stubs(:check_url).returns(fetch_guard_allowed)
    Distillator::FetchGuard.stubs(:check_response).returns(fetch_guard_allowed)
    Distillator::FetchService.expects(:legacy_fetch).returns(
      status: :ok,
      body: "<html>legacy</html>",
      wringer: { signals: {}, hints: [] }
    )
    Distillator::FetchService.expects(:internal_fetch).returns(
      status: :ok,
      body: "<html>internal</html>",
      headers: { content_type: "text/html" },
      final_url: "https://example.com/events",
      redirect_chain: [],
      wringer: { signals: {}, hints: [] }
    )
    Distillator::FetchShadowComparator.expects(:compare).once

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      website: website,
      log_context: { statement_id: 11, source_id: 22, webpage_id: 33, website_id: website.id },
      logger: logger
    )

    assert_equal "<html>legacy</html>", result[:body]
    assert_equal "shadow", logger.infos.last[:mode]
    assert_equal "fetch.shadow_compare", logger.infos.last[:event]
    assert_equal "website", logger.infos.last[:mode_source]
    assert_equal 11, logger.infos.last[:statement_id]
    assert_equal 22, logger.infos.last[:source_id]
    assert_equal 33, logger.infos.last[:webpage_id]
    assert_equal website.id, logger.infos.last[:website_id]
  end

  test "legacy website preserves current behavior when global mode is internal" do
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    logger = CapturingLogger.new
    website = websites(:one)
    website.update!(distillator_mode: "legacy")

    Distillator::FetchService.expects(:internal_fetch).never
    Distillator::FetchService.expects(:legacy_fetch).returns(
      status: :ok,
      body: "<html>legacy</html>",
      wringer: { signals: {}, hints: [] }
    )

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      website: website,
      logger: logger
    )

    assert_equal "<html>legacy</html>", result[:body]
    assert_equal "legacy", logger.infos.last[:mode]
    assert_equal "website", logger.infos.last[:mode_source]
  end

  private

  def fetch_guard_allowed
    Distillator::FetchGuard::Result.new(allowed: true)
  end
end
