require "test_helper"
require "webmock/minitest"
require "ostruct"

class DslAlgorithmRunnerTest < ActiveSupport::TestCase
  include DslRunnerTestHelper

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
    @previous_legacy_wringer_fallback = ENV["DISTILLATOR_LEGACY_WRINGER_FALLBACK"]
    ENV["DISTILLATOR_LEGACY_WRINGER_FALLBACK"] = nil
  end

  teardown do
    ENV["DISTILLATOR_LEGACY_WRINGER_FALLBACK"] = @previous_legacy_wringer_fallback
  end

  def build_runner(*args, url: nil, scrape_options: {}, tracer: Dsl::Tracing::TraceCollector.new, render_js: false)
    start_url = url || args.first || "http://example.local"
    super(url: start_url, scrape_options: scrape_options, tracer: tracer, render_js: render_js)
  end

  def build_compat_runner(*args, url: nil, scrape_options: {}, tracer: Dsl::Tracing::TraceCollector.new, render_js: false)
    start_url = url || args.first || "http://example.local"
    super(url: start_url, scrape_options: scrape_options, tracer: tracer, render_js: render_js)
  end

  test "manual prefix returns configured literal" do
    expect_no_fetch_seams
    runner, = build_runner_with_html
    result = runner.run("manual=hello")

    assert_equal ["hello"], result
    assert_no_wringer_requests
  end

  test "trace uses inherited wringer context for non-fetch steps" do
    expect_no_fetch_seams
    runner, tracer = build_runner

    runner.run("manual=hello")
    step = tracer.to_h.first

    assert_equal true, step.dig(:wringer, :inherited)
    assert_no_wringer_requests
  end

  test "trace marks probe as skipped when not executed" do
    expect_no_fetch_seams
    runner, tracer = build_runner

    runner.run("manual=hello")
    step = tracer.to_h.first

    assert_equal true, step.dig(:probe, :skipped)
    assert_no_wringer_requests
  end

  test "syntax error in ruby returns abort_update payload instead of raising" do
    expect_no_fetch_seams
    runner, = build_runner_with_html
    result = runner.run("ruby=$array.each {|a| a")

    assert_equal "abort_update", result.first
    assert_match(/syntax error/i, result.last[:error])
    assert_no_wringer_requests
  end

  test "if_xpath short-circuits subsequent steps when no match" do
    expect_no_fetch_seams
    runner, = build_runner_with_html(html: "<html><body><h1>Title</h1></body></html>")
    result = runner.run("if_xpath=//missing; xpath=//h1/text()")

    assert_equal [], result
    assert_no_wringer_requests
  end

  test "unless_xpath short-circuits subsequent steps when match exists" do
    expect_no_fetch_seams
    runner, = build_runner_with_html(html: "<html><body><h1>Title</h1></body></html>")
    result = runner.run("unless_xpath=//h1; xpath=//h1/text()")

    assert_equal [], result
    assert_no_wringer_requests
  end

  test "if_xpath emits matches but later step replaces result" do
    expect_no_fetch_seams
    runner, = build_runner_with_html(html: "<html><body><title>T</title><h1>H</h1></body></html>")
    result = runner.run("if_xpath=//title; xpath=//h1/text()")

    assert_equal ["H"], result
    assert_no_wringer_requests
  end

  test "ruby step uses eval result rather than stale thread local array" do
    expect_no_fetch_seams
    runner, = build_runner_with_html(html: "<html><body><p>a</p><p>b</p></body></html>")
    result = runner.run("xpath=//p/text(); ruby=$array.map(&:upcase)")

    assert_equal %w[A B], result
    assert_no_wringer_requests
  end

  test "ensure_page fetches through Distillator" do
    runner, = build_runner("http://example.local/start")

    fetch = distillator_fetch_response(
      final_url: "http://example.local/start",
      duration_ms: 7
    )

    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "http://example.local/start", kwargs[:uri]
      assert_equal false, kwargs[:render_js]
      assert_equal true, kwargs[:include_fragment]
      assert_equal :use_wringer, kwargs[:use_wringer].name
      assert_equal :safe_wringer_call, kwargs[:safe_wringer_call].name
      true
    end.returns(fetch)

    result = runner.run("xpath=//h1/text()")

    assert_equal ["Title"], result
  end

  test "api returns parsed json payload as current result" do
    stub_request(:get, "http://api.example.local/data").to_return(
      status: 200,
      body: { "name" => "Jane" }.to_json
    )

    runner, = build_runner
    result = runner.run("api='http://api.example.local/data'")

    assert_equal({ "name" => "Jane" }, result)
  end

  test "sparql fetches graph source through Distillator" do
    runner, = build_runner("http://example.local/event")

    ttl = <<~TTL
      @prefix schema: <http://schema.org/> .
      <http://example.local/event> schema:name "Event Name" .
    TTL
    fetch = distillator_fetch_response(
      body: <<~TTL,
        @prefix schema: <http://schema.org/> .
        <http://example.local/event> schema:name "Event Name" .
      TTL
      html: ttl,
      headers: { content_type: "text/turtle" },
      final_url: "http://example.local/event",
      duration_ms: 11
    )

    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "http://example.local/event", kwargs[:uri]
      assert_equal false, kwargs[:render_js]
      assert_equal true, kwargs[:include_fragment]
      true
    end.returns(fetch)
    rows = [OpenStruct.new(answer: OpenStruct.new(value: "Event Name"))]
    SPARQL.expects(:execute)
      .with do |query, graph|
        assert_equal "PREFIX schema: <http://schema.org/> select * where {?s schema:name ?answer}", query
        assert_instance_of RDF::Graph, graph
        true
      end
      .returns(rows)

    result = runner.run("sparql={?s schema:name ?answer}")
    assert_equal ["Event Name"], result
  end

  test "run_dsl internal mode routes page fetches through Distillator fetch cache store" do
    previous_mode = ENV["DISTILLATOR_FETCH_MODE"]
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    runner, = build_runner("https://example.com/start")

    fetch = distillator_fetch_response(
      final_url: "https://example.com/start",
      duration_ms: 5
    )

    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "https://example.com/start", kwargs[:uri]
      assert_equal false, kwargs[:render_js]
      assert_equal true, kwargs[:include_fragment]
      assert_same runner.instance_variable_get(:@agent), kwargs[:agent]
      true
    end.returns(fetch)

    result = runner.run("xpath=//h1/text()")

    assert_equal ["Title"], result
  ensure
    ENV["DISTILLATOR_FETCH_MODE"] = previous_mode
  end

  test "crawl cache options route eligible html fetches through Distillator fetch cache" do
    tracer = Dsl::Tracing::TraceCollector.new
    ctx = {
      url: "https://example.com/start",
      render_js: false,
      scrape_options: { force_scrape_every_hrs: "1" },
      tracer: tracer
    }
    runner = Dsl::Core::AlgorithmRunner.new(ctx)
    fetch = distillator_fetch_response(
      final_url: "https://example.com/start",
      signals: { "network_status" => "ok" },
      cache_reason: "stale_by_force_scrape_every_hrs",
    )
    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "https://example.com/start", kwargs[:uri]
      assert_equal false, kwargs[:render_js]
      assert_equal true, kwargs[:include_fragment]
      assert_equal "1", kwargs[:force_scrape_every_hrs]
      assert_equal false, kwargs[:json_post]
      assert_nil kwargs[:website]
      assert_nil kwargs[:website_id]
      assert_same runner.instance_variable_get(:@agent), kwargs[:agent]
      true
    end.returns(fetch)

    result = runner.run("xpath=//h1/text()")

    assert_equal ["Title"], result
  end

  test "native refresh forwards mode cache options and log context into Distillator fetch cache store" do
    previous_mode = ENV["DISTILLATOR_FETCH_MODE"]
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    tracer = Dsl::Tracing::TraceCollector.new
    ctx = {
      url: "https://example.com/native",
      render_js: false,
      scrape_options: {
        force_scrape_every_hrs: "0",
        absolute_src: true,
        log_context: { statement_id: 41, source_id: 42, webpage_id: 43, website_id: 44 }
      },
      tracer: tracer
    }
    runner = Dsl::Core::AlgorithmRunner.new(ctx)
    fetch = distillator_fetch_response(
      final_url: "https://example.com/native",
      signals: { "network_status" => "ok" },
      cache_reason: "stale_by_force_scrape_every_hrs",
    )

    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "https://example.com/native", kwargs[:uri]
      assert_nil kwargs[:mode]
      assert_equal "0", kwargs[:force_scrape_every_hrs]
      assert_equal true, kwargs[:absolute_src]
      assert_nil kwargs[:website]
      assert_equal 44, kwargs[:website_id]
      assert_equal({ statement_id: 41, source_id: 42, webpage_id: 43, website_id: 44 }, kwargs[:log_context])
      true
    end.returns(fetch)

    result = runner.run("xpath=//h1/text()")

    assert_equal ["Title"], result
  ensure
    ENV["DISTILLATOR_FETCH_MODE"] = previous_mode
  end

  test "explicit diagnostic mode is forwarded to Distillator fetch cache store" do
    tracer = Dsl::Tracing::TraceCollector.new
    runner = Dsl::Core::AlgorithmRunner.new(
      url: "https://example.com/diagnostic",
      render_js: false,
      scrape_options: {
        mode: "internal",
        log_context: { website_id: 44 }
      },
      tracer: tracer
    )
    fetch = distillator_fetch_response(
      final_url: "https://example.com/diagnostic",
      signals: { "network_status" => "ok" }
    )

    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal :internal, kwargs[:mode]
      assert_equal 44, kwargs[:website_id]
      true
    end.returns(fetch)

    assert_equal ["Title"], runner.run("xpath=//h1/text()")
  end

  test "invalid explicit diagnostic mode is ignored during statement refresh" do
    tracer = Dsl::Tracing::TraceCollector.new
    runner = Dsl::Core::AlgorithmRunner.new(
      url: "https://example.com/invalid-mode",
      render_js: false,
      scrape_options: {
        mode: "bogus",
        log_context: { website_id: 55 }
      },
      tracer: tracer
    )
    fetch = distillator_fetch_response(
      final_url: "https://example.com/invalid-mode",
      signals: { "network_status" => "ok" }
    )

    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_nil kwargs[:mode]
      assert_equal 55, kwargs[:website_id]
      true
    end.returns(fetch)

    assert_equal ["Title"], runner.run("xpath=//h1/text()")
  end

  test "render_js and json_post options are passed through Distillator fetch cache store" do
    tracer = Dsl::Tracing::TraceCollector.new
    ctx = {
      url: "https://example.com/api",
      render_js: true,
      scrape_options: { json_post: true, force_scrape_every_hrs: "24" },
      tracer: tracer
    }
    runner = Dsl::Core::AlgorithmRunner.new(ctx)
    fetch = distillator_fetch_response(
      final_url: "https://example.com/api",
      signals: { "network_status" => "ok" },
      cache_reason: "stale_by_force_scrape_every_hrs",
      fetch_path: "legacy"
    )

    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "https://example.com/api", kwargs[:uri]
      assert_equal true, kwargs[:render_js]
      assert_equal true, kwargs[:include_fragment]
      assert_equal true, kwargs[:json_post]
      assert_equal "24", kwargs[:force_scrape_every_hrs]
      assert_nil kwargs[:website]
      assert_nil kwargs[:website_id]
      true
    end.returns(fetch)

    result = runner.run("xpath=//h1/text()")

    assert_equal ["Title"], result
  end

  test "env legacy mode does not override website active rollout during statement refresh" do
    previous_mode = ENV["DISTILLATOR_FETCH_MODE"]
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"

    website = websites(:one)
    website.update!(distillator_mode: "active")

    tracer = Dsl::Tracing::TraceCollector.new
    runner = Dsl::Core::AlgorithmRunner.new(
      url: "https://example.com/active",
      render_js: false,
      scrape_options: {
        website: website,
        website_id: website.id,
        log_context: { website_id: website.id }
      },
      tracer: tracer
    )

    fetch = distillator_fetch_response(
      final_url: "https://example.com/active",
      body: "<html><body><h1>Active</h1></body></html>",
    )

    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_nil kwargs[:mode], "DSL runner must not convert ENV into explicit mode"
      assert_equal website, kwargs[:website]
      assert_equal website.id, kwargs[:website_id]
      true
    end.returns(fetch)

    assert_equal ["Active"], runner.run("xpath=//h1/text()")
  ensure
    ENV["DISTILLATOR_FETCH_MODE"] = previous_mode
  end

  test "failed distillator cache fetch paths abort before extraction and preserve downstream statement state" do
    cases = [
      {
        name: "normal get transport failure",
        final_url: "https://example.com/timeout",
        http_response_code: nil,
        fetch_path: "native",
        signals: {
          "network_status" => "failed",
          "blocking_issue_key" => "timeout",
          "content_success" => false,
          "transport_success" => false
        },
        hints: ["timeout"],
        error_type: "timeout"
      },
      {
        name: "normal get non 2xx",
        final_url: "https://example.com/server-error",
        http_response_code: 500,
        fetch_path: "native",
        signals: {
          "network_status" => "ok",
          "blocking_issue_key" => "http_server_error",
          "content_success" => false,
          "transport_success" => false
        },
        hints: ["http_server_error"],
        error_type: "http_server_error"
      },
      {
        name: "rendered failure",
        final_url: "https://example.com/eventsiframe",
        http_response_code: 500,
        fetch_path: "native",
        signals: {
          "network_status" => "ok",
          "renderer" => "legacy_phantomjs",
          "blocking_issue_key" => "phantomjs_iframe_missing_child_content",
          "content_success" => false,
          "transport_success" => false
        },
        hints: ["legacy_phantomjs", "phantomjs_iframe_missing_child_content"],
        error_type: "phantomjs_iframe_missing_child_content"
      },
      {
        name: "post failure",
        final_url: "https://example.com/api",
        http_response_code: 500,
        fetch_path: "native",
        signals: {
          "network_status" => "ok",
          "request_method" => "POST",
          "blocking_issue_key" => "http_server_error",
          "content_success" => false,
          "transport_success" => false
        },
        hints: ["json_detected", "http_server_error"],
        error_type: "http_server_error"
      },
      {
        name: "blocked url",
        final_url: "http://127.0.0.1/events",
        http_response_code: nil,
        fetch_path: "blocked",
        signals: {
          "network_status" => "blocked",
          "native_ineligible_reason" => "blocked_url",
          "blocking_issue_key" => "blocked_url",
          "content_success" => false,
          "transport_success" => false
        },
        hints: ["blocked_url", "blocked"],
        error_type: "blocked_url"
      },
      {
        name: "content failure",
        final_url: "https://www.ovation.ca/Search/Title/",
        http_response_code: 200,
        fetch_path: "native",
        signals: {
          "network_status" => "ok",
          "blocking_issue_key" => "redirect_to_listing",
          "primary_issue_key" => "redirect_to_listing",
          "content_success" => false,
          "transport_success" => true
        },
        hints: ["redirect_to_listing"],
        error_type: "redirect_to_listing"
      }
    ]

    cases.each do |test_case|
      runner, tracer = build_runner(url: "https://example.com/start")
      Distillator::FetchCacheStore.expects(:fetch).returns(
        failed_cache_fetch_result(
          final_url: test_case[:final_url],
          http_response_code: test_case[:http_response_code],
          fetch_path: test_case[:fetch_path],
          signals: test_case[:signals],
          hints: test_case[:hints]
        )
      )

      result = runner.run("xpath=//h1/text();ruby=['SHOULD_NOT_RUN']")

      assert_equal "abort_update", result.first, test_case[:name]
      assert_equal test_case[:error_type], result.last[:error_type], test_case[:name]
      assert_equal "distillator_fetch_cache", result.last[:source], test_case[:name]
      assert_equal "url", result.last[:step], test_case[:name]
      assert_equal 1, tracer.to_h.size, test_case[:name]
      assert_equal "xpath", tracer.to_h.first[:type], test_case[:name]
    end
  end

  test "thread locals are restored after aborted execution" do
    Thread.current[:dsl_array] = ["existing"]
    Thread.current[:dsl_url] = "existing-url"
    Thread.current[:dsl_json] = { "existing" => true }

    runner, = build_runner
    result = runner.run("ruby=$array.each {|a| a")

    assert_equal "abort_update", result.first
    assert_equal ["existing"], Thread.current[:dsl_array]
    assert_equal "existing-url", Thread.current[:dsl_url]
    assert_equal({ "existing" => true }, Thread.current[:dsl_json])
  ensure
    Thread.current[:dsl_array] = nil
    Thread.current[:dsl_url] = nil
    Thread.current[:dsl_json] = nil
  end

  test "trace event includes wringer status when safe_wringer_call aborts" do
    runner, tracer = build_runner
    fetch = distillator_fetch_response(
      status: :abort,
      body: ["abort_update", { error_type: "system_cloudflare", error: "Cloudflare blocked", retry: true, cache: false }],
      headers: {},
      final_url: "http://example.local/events/1",
      html: nil,
      http_response_code: nil,
      signals: { "error_type" => "system_cloudflare" },
      duration_ms: 12,
      fetch_path: "legacy"
    )
    Distillator::FetchCacheStore.stubs(:fetch).returns(fetch)

    result = runner.run("url='http://example.local/events/1'")
    event = tracer.to_h.last

    assert_equal "abort_update", result.first
    assert_equal "system_cloudflare", event[:wringer][:error_type]
    assert_equal true, event[:wringer][:retry]
    assert_equal false, event[:wringer][:cache]
    assert_equal({ "error_type" => "system_cloudflare" }, event[:wringer][:signals])
    assert_equal [], event[:wringer][:hints]
  end

  test "trace event wringer status includes diagnostics when safe_wringer_call succeeds" do
    runner, tracer = build_runner
    fetch = distillator_fetch_response(
      final_url: "http://example.local/events/1",
      signals: { "network_status" => "ok", "content_type" => "html", "redirect_type" => "none", "redirected" => false, "final_url" => "http://example.local/events/1" },
      duration_ms: 9,
    )
    Distillator::FetchCacheStore.stubs(:fetch).returns(fetch)

    result = runner.run("url='http://example.local/events/1';xpath=//h1/text()")
    url_step_event = tracer.to_h.first

    assert_equal ["Title"], result
    assert_equal fetch.signals, url_step_event[:wringer][:signals]
    assert_equal [], url_step_event[:wringer][:hints]
  end

  test "trace event safely includes partial wringer payload keys only" do
    runner, tracer = build_runner
    fetch = distillator_fetch_response(
      status: :abort,
      body: ["abort_update", { error_type: "system_cloudflare", error: "Cloudflare blocked" }],
      headers: {},
      final_url: "http://example.local/events/1",
      html: nil,
      http_response_code: nil,
      signals: { "error_type" => "system_cloudflare" },
      duration_ms: 12,
      fetch_path: "legacy"
    )
    Distillator::FetchCacheStore.stubs(:fetch).returns(fetch)

    result = runner.run("url='http://example.local/events/1'")
    event = tracer.to_h.last

    assert_equal "abort_update", result.first
    assert_equal "system_cloudflare", event[:wringer][:error_type]
    assert_equal({ "error_type" => "system_cloudflare" }, event[:wringer][:signals])
    assert_equal [], event[:wringer][:hints]
  end

  test "trace includes wringer duration from client" do
    runner, tracer = build_runner

    fetch = distillator_fetch_response(
      body: "<html>ok</html>",
      headers: {},
      final_url: "http://example.local/events/1",
      duration_ms: 123
    )

    Distillator::FetchCacheStore.stubs(:fetch).returns(fetch)

    runner.run("url='http://example.local/events/1'")

    trace = tracer.to_h
    step = trace.find { |s| s[:wringer].is_a?(Hash) }

    assert_equal 123, step[:wringer][:duration_ms]
  end

  test "trace includes wringer final_url and redirect_chain" do
    runner, tracer = build_runner

    fetch = distillator_fetch_response(
      body: "<html>ok</html>",
      headers: {},
      final_url: "https://final.example.com",
      redirect_chain: ["http://start", "https://final.example.com"],
      duration_ms: 50
    )

    Distillator::FetchCacheStore.stubs(:fetch).returns(fetch)

    runner.run("url='http://example.local/events/1'")

    trace = tracer.to_h
    step = trace.find { |s| s[:wringer].is_a?(Hash) }

    assert_equal "https://final.example.com", step[:wringer][:final_url]
    assert_equal ["http://start", "https://final.example.com"], step[:wringer][:redirect_chain]
  end

  test "probe abort is not converted into a successful probe payload" do
    runner, = build_runner
    runner.stubs(:execute_xpath).with("//title").returns(
      ["abort_update", { error: "Probe fetch failed", error_type: "ProbeAbort", step: "xpath", source: "dsl_runner" }]
    )

    probe = runner.send(:build_xpath_probe, "url", "xpath", [], 1)

    assert_equal "abort_update", probe.first
    assert_equal "ProbeAbort", probe.last[:error_type]
  end

  test "probe abort stops pipeline and prevents downstream steps" do
    runner, tracer = build_compat_runner
    runner.stubs(:safe_wringer_call).returns("<html><body><h1>ok</h1></body></html>")
    runner.stubs(:execute_xpath).with("//h1/text()").returns([])
    runner.stubs(:execute_xpath).with("//title").returns(
      ["abort_update", { error: "Probe fetch failed", error_type: "ProbeAbort", step: "xpath", source: "dsl_runner" }]
    )

    result = runner.run("url='http://example.local/page';xpath=//h1/text();ruby=['SHOULD_NOT_RUN']")

    assert_equal "abort_update", result.first
    assert_equal "ProbeAbort", result.last[:error_type]
    assert_equal 2, tracer.to_h.size
    assert_equal "xpath", tracer.to_h.last[:type]
  end

  test "url step resolving to nil aborts and traces abort step without running later steps" do
    runner, tracer = build_compat_runner
    runner.stubs(:safe_wringer_call).returns("<html><body><h1>Fresh</h1></body></html>")
    runner.expects(:execute_xpath).never

    result = runner.run("url='http://example.local/page';url=nil;xpath=//h1/text()")

    assert_equal "abort_update", result.first
    assert_equal "InvalidURL", result.last[:error_type]
    assert_equal "url", result.last[:step]
    assert_match(/invalid url/i, result.last[:error].to_s)

    events = tracer.to_h
    assert_equal 2, events.size
    assert_equal "url", events.second[:type]
    assert_equal "Hash", events.second[:error_class]
    assert_match(/InvalidURL/, events.second[:error_message].to_s)
    assert_match(/step=url/, events.second[:error_message].to_s)
  end

  test "non trace runner aborts on nil resolved url and does not reuse previous page state" do
    ctx = {
      url: "http://example.local",
      render_js: false,
      scrape_options: { wringer_compatibility: true },
      tracer: Dsl::Tracing::NullTracer.new
    }
    runner = Dsl::Core::AlgorithmRunner.new(ctx)
    runner.stubs(:safe_wringer_call).returns("<html><body><h1>Fresh</h1></body></html>")
    runner.expects(:execute_xpath).never

    result = runner.run("url='http://example.local/page';url=nil;xpath=//h1/text()")

    assert_equal "abort_update", result.first
    assert_equal "InvalidURL", result.last[:error_type]
    assert_equal "url", result.last[:step]
    assert_equal "dsl_runner", result.last[:source]
  end

  test "ensure_page abort stops pipeline without raising and prevents downstream ruby" do
    runner, tracer = build_compat_runner
    runner.stubs(:safe_wringer_call).returns(["abort_update", { error: "Wringer unreachable", error_type: "SocketError" }])

    result = runner.run("xpath=//h1/text();ruby=$array.map(&:upcase)")

    assert_equal "abort_update", result.first
    assert_equal "SocketError", result.last[:error_type]
    assert_equal "xpath", result.last[:step]
    assert_equal "dsl_runner", result.last[:source]

    events = tracer.to_h
    assert_equal 1, events.size
    assert_equal "xpath", events.first[:type]
  end

  test "wringer abort source is preserved when upstream provides it" do
    runner, = build_compat_runner
    runner.stubs(:safe_wringer_call).returns(
      ["abort_update", { error: "Wringer unreachable", error_type: "SocketError", source: "wringer" }]
    )

    result = runner.run("xpath=//h1/text()")

    assert_equal "abort_update", result.first
    assert_equal "wringer", result.last[:source]
    assert_equal "xpath", result.last[:step]
  end

  test "resolve_url_only nil URL aborts in api step without silent continuation" do
    runner, tracer = build_compat_runner

    result = runner.run("api=nil;ruby=['SHOULD_NOT_RUN']")

    assert_equal "abort_update", result.first
    assert_equal "InvalidURL", result.last[:error_type]
    assert_equal "api", result.last[:step]
    assert_equal "dsl_runner", result.last[:source]

    events = tracer.to_h
    assert_equal 1, events.size
    assert_equal "api", events.first[:type]
  end

  test "trace and non-trace runs return identical abort payload for invalid URL" do
    trace_runner, = build_runner
    trace_result = trace_runner.run("api=nil")

    non_trace_runner = Dsl::Core::AlgorithmRunner.new(
      url: "http://example.local",
      render_js: false,
      scrape_options: {},
      tracer: Dsl::Tracing::NullTracer.new
    )
    non_trace_result = non_trace_runner.run("api=nil")

    assert_equal trace_result, non_trace_result
    assert_equal "abort_update", trace_result.first
    assert_equal "dsl_runner", trace_result.last[:source]
  end

  test "trace events always include wringer signals and hints keys" do
    runner, tracer = build_compat_runner
    runner.run("manual=hello")

    wringer = tracer.to_h.first[:wringer]
    assert wringer.key?(:signals)
    assert wringer.key?(:hints)
    assert_equal({}, wringer[:signals])
    assert_equal [], wringer[:hints]
  end

  test "all abort payloads include error error_type and source" do
    runner, = build_runner
    result = runner.run("api=nil")

    assert_equal "abort_update", result.first
    assert result.last[:error].is_a?(String)
    assert result.last[:error_type].is_a?(String)
    assert result.last[:source].is_a?(String)
  end

  test "runner uses single abort_update contract without tuple wrappers" do
    source = File.read(Rails.root.join("app/services/dsl/core/algorithm_runner.rb"))

    refute_match(/def\s+ok\(/, source)
    refute_match(/def\s+abort\(/, source)
    refute_match(/\[:abort,/, source)
  end

  test "xpath probe runs only when xpath is empty after url step" do
    expect_no_fetch_seams
    runner, tracer = build_runner
    runner.stubs(:resolve_and_fetch_url).returns("<html><body><p>body</p></body></html>")
    runner.expects(:execute_xpath).with("//h1/text()").returns([])
    runner.expects(:execute_xpath).with("//title").returns(["Probe Title"])

    result = runner.run("url='http://example.local/events/1';xpath=//h1/text()")

    assert_equal [], result

    url_event = tracer.to_h.first
    xpath_event = tracer.to_h.second

    assert_equal true, url_event.dig(:probe, :skipped)
    assert_equal "//title", xpath_event.dig(:probe, :result, :xpath)
    assert_equal ["Probe Title"], xpath_event.dig(:probe, :result, :output)
    assert_no_wringer_requests
  end

  test "xpath probe does not run for empty xpath when previous step is not url" do
    expect_no_fetch_seams
    runner, tracer = build_runner
    runner.expects(:execute_xpath).with("//h1/text()").returns([])
    runner.expects(:execute_xpath).with("//title").never

    result = runner.run("xpath=//h1/text()")

    assert_equal [], result
    assert_equal true, tracer.to_h.first.dig(:probe, :skipped)
    assert_no_wringer_requests
  end

  test "xpath probe is attached only to first empty xpath after url" do
    expect_no_fetch_seams
    runner, tracer = build_runner
    runner.stubs(:resolve_and_fetch_url).returns("<html><body><p>body</p></body></html>")
    runner.expects(:execute_xpath).with("//h1/text()").returns([])
    runner.expects(:execute_xpath).with("//title").returns(["Probe Title"])
    runner.expects(:execute_xpath).with("//h2/text()").returns([])

    result = runner.run("url='http://example.local/events/1';xpath=//h1/text();xpath=//h2/text()")

    assert_equal [], result

    events = tracer.to_h
    assert_equal true, events.first.dig(:probe, :skipped)
    assert_equal "//title", events.second.dig(:probe, :result, :xpath)
    assert_equal true, events.third.dig(:probe, :skipped)
    assert_no_wringer_requests
  end

  test "xpath probe triggers for all blank outputs after url step" do
    [[], nil, "", "   "].each do |blank_output|
      runner, = build_runner
      runner.stubs(:execute_xpath).returns(["Probe Title"])

      probe = runner.send(:build_xpath_probe, "url", "xpath", blank_output, 1)

      assert_equal "//title", probe[:xpath]
      assert_equal ["Probe Title"], probe[:output]
    end
  end

  test "xpath probe structure is normalized" do
    runner, = build_runner
    runner.stubs(:execute_xpath).returns([nil, "Alpha", :beta, "Gamma", "Delta"])

    probe = runner.send(:build_xpath_probe, "url", "xpath", [], 1)

    assert_equal "ok", probe[:status]
    assert_equal "//title", probe[:xpath]
    assert_equal ["Alpha", "beta", "Gamma"], probe[:output]
    assert_operator probe[:output].size, :<=, 3
    assert probe[:output].all? { |entry| entry.is_a?(String) }
  end

  test "xpath probe exception is explicit error and never reported as ok" do
    runner, = build_runner
    runner.stubs(:execute_xpath).with("//title").raises(StandardError, "probe exploded")

    probe = runner.send(:build_xpath_probe, "url", "xpath", [], 1)

    assert_equal "error", probe[:status]
    assert_equal true, probe[:exception]
    assert_equal "//title", probe[:xpath]
    assert_equal [], probe[:output]
  end

  test "abort_update and normalize_abort_result share the same core payload shape" do
    runner, = build_runner

    direct = runner.send(
      :abort_update,
      error: "Invalid URL resolved from nil",
      error_type: "InvalidURL",
      step: "url",
      source: "dsl_runner"
    )
    normalized = runner.send(
      :normalize_abort_result,
      ["abort_update", { error: "Invalid URL resolved from nil", error_type: "InvalidURL", step: "url", source: "dsl_runner", retry: true }],
      step: "url"
    )

    assert_equal "abort_update", direct.first
    assert_equal "abort_update", normalized.first
    assert_equal direct.last.slice(:error, :error_type, :step, :source), normalized.last.slice(:error, :error_type, :step, :source)
    assert_equal true, normalized.last[:retry]
  end

  test "xpath probe does not run for xpath to xpath empty chain" do
    expect_no_fetch_seams
    runner, tracer = build_runner
    runner.expects(:execute_xpath).with("//h1/text()").returns([])
    runner.expects(:execute_xpath).with("//h2/text()").returns([])
    runner.expects(:execute_xpath).with("//title").never

    result = runner.run("xpath=//h1/text();xpath=//h2/text()")

    assert_equal [], result
    assert_equal true, tracer.to_h.first.dig(:probe, :skipped)
    assert_equal true, tracer.to_h.second.dig(:probe, :skipped)
    assert_no_wringer_requests
  end

  test "xpath probe stays trace-only and does not change pipeline output" do
    expect_no_fetch_seams
    runner, tracer = build_runner
    runner.stubs(:resolve_and_fetch_url).returns("<html><body><p>body</p></body></html>")
    runner.expects(:execute_xpath).with("//h1/text()").returns([])
    runner.expects(:execute_xpath).with("//title").returns(["SHOULD_NOT_REPLACE_OUTPUT"])

    result = runner.run("url='http://example.local/events/1';xpath=//h1/text()")
    probe_output = tracer.to_h.second.dig(:probe, :result, :output)

    assert_equal [], result
    assert_equal ["SHOULD_NOT_REPLACE_OUTPUT"], probe_output
    refute_equal probe_output, result
    assert_no_wringer_requests
  end

  def failed_cache_fetch_result(final_url:, http_response_code:, fetch_path:, signals:, hints:)
    OpenStruct.new(
      status: :ok,
      body: "<html>failed replacement</html>",
      html: nil,
      headers: { content_type: "text/html" },
      final_url: final_url,
      redirect_chain: [final_url],
      http_response_code: http_response_code,
      signals: signals,
      hints: hints,
      duration_ms: 0,
      cache_hit: false,
      cache_write: true,
      cache_reason: "force_scrape",
      uri_key: CGI.escape(final_url),
      normalized_url: final_url,
      fetch_path: fetch_path
    ).tap do |fetch|
      fetch.define_singleton_method(:content_success?) { false }
      fetch.define_singleton_method(:cache_policy) { false }
      fetch.define_singleton_method(:retry_policy) { false }
    end
  end
end
