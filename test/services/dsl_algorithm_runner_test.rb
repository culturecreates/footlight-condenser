require "test_helper"
require "webmock/minitest"
require "ostruct"

class DslAlgorithmRunnerTest < ActiveSupport::TestCase
  setup do
    stub_request(:get, /.*/).to_return(status: 200, body: "", headers: {})
  end

  def build_runner(start_url = "http://example.local")
    tracer = Dsl::DslTraceCollector.new
    ctx = {
      url: start_url,
      render_js: false,
      scrape_options: {},
      tracer: tracer
    }
    [Dsl::DslAlgorithmRunner.new(ctx), tracer]
  end

  test "manual prefix returns configured literal" do
    runner, = build_runner
    result = runner.run("manual=hello")

    assert_equal ["hello"], result
  end

  test "trace uses inherited wringer context for non-fetch steps" do
    runner, tracer = build_runner

    runner.run("manual=hello")
    step = tracer.to_h.first

    assert_equal true, step.dig(:wringer, :inherited)
  end

  test "trace marks probe as skipped when not executed" do
    runner, tracer = build_runner

    runner.run("manual=hello")
    step = tracer.to_h.first

    assert_equal true, step.dig(:probe, :skipped)
  end

  test "syntax error in ruby returns abort_update payload instead of raising" do
    runner, = build_runner
    result = runner.run("ruby=$array.each {|a| a")

    assert_equal "abort_update", result.first
    assert_match(/syntax error/i, result.last[:error])
  end

  test "if_xpath short-circuits subsequent steps when no match" do
    html = "<html><body><h1>Title</h1></body></html>"
    stub_request(:get, /localhost:3009\/websites\/wring/).to_return(status: 200, body: html)

    runner, = build_runner
    result = runner.run("if_xpath=//missing; xpath=//h1/text()")

    assert_equal [], result
  end

  test "unless_xpath short-circuits subsequent steps when match exists" do
    html = "<html><body><h1>Title</h1></body></html>"
    stub_request(:get, /localhost:3009\/websites\/wring/).to_return(status: 200, body: html)

    runner, = build_runner
    result = runner.run("unless_xpath=//h1; xpath=//h1/text()")

    assert_equal [], result
  end

  test "if_xpath emits matches but later step replaces result" do
    html = "<html><body><title>T</title><h1>H</h1></body></html>"
    stub_request(:get, /localhost:3009\/websites\/wring/).to_return(status: 200, body: html)

    runner, = build_runner
    result = runner.run("if_xpath=//title; xpath=//h1/text()")

    assert_equal ["H"], result
  end

  test "ruby step uses eval result rather than stale thread local array" do
    html = "<html><body><p>a</p><p>b</p></body></html>"
    stub_request(:get, /localhost:3009\/websites\/wring/).to_return(status: 200, body: html)

    runner, = build_runner
    result = runner.run("xpath=//p/text(); ruby=$array.map(&:upcase)")

    assert_equal %w[A B], result
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

  test "sparql loads graph via wringer url" do
    runner, = build_runner("http://example.local/event")

    graph = Object.new
    RDF::Graph.expects(:load).with { |arg| arg.match?(%r{localhost:3009/websites/wring\?}) }.returns(graph)
    rows = [OpenStruct.new(answer: OpenStruct.new(value: "Event Name"))]
    SPARQL.expects(:execute)
      .with("PREFIX schema: <http://schema.org/> select * where {?s schema:name ?answer}", graph)
      .returns(rows)

    result = runner.run("sparql={?s schema:name ?answer}")
    assert_equal ["Event Name"], result
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
    runner.stubs(:safe_wringer_call).returns(
      ["abort_update", { error_type: "system_cloudflare", retry: true, cache: false }]
    )

    result = runner.run("url='http://example.local/events/1'")
    event = tracer.to_h.last

    assert_equal "abort_update", result.first
    assert_equal "system_cloudflare", event[:wringer][:error_type]
    assert_equal true, event[:wringer][:retry]
    assert_equal false, event[:wringer][:cache]
    assert_equal({}, event[:wringer][:signals])
    assert_equal [], event[:wringer][:hints]
  end

  test "trace event wringer status includes diagnostics when safe_wringer_call succeeds" do
    runner, tracer = build_runner
    runner.stubs(:safe_wringer_call).returns("<html><body><h1>Title</h1></body></html>")

    result = runner.run("url='http://example.local/events/1';xpath=//h1/text()")
    url_step_event = tracer.to_h.first

    assert_equal ["Title"], result
    assert_equal({}, url_step_event[:wringer][:signals])
    assert_equal [], url_step_event[:wringer][:hints]
  end

  test "trace event safely includes partial wringer payload keys only" do
    runner, tracer = build_runner
    runner.stubs(:safe_wringer_call).returns(
      ["abort_update", { error_type: "system_cloudflare" }]
    )

    result = runner.run("url='http://example.local/events/1'")
    event = tracer.to_h.last

    assert_equal "abort_update", result.first
    assert_equal "system_cloudflare", event[:wringer][:error_type]
    assert_equal({}, event[:wringer][:signals])
    assert_equal [], event[:wringer][:hints]
  end

  test "trace includes wringer duration from client" do
    runner, tracer = build_runner

    fake_result = {
      body: "<html>ok</html>",
      wringer: {
        error_type: nil,
        signals: {},
        hints: []
      },
      duration_ms: 123
    }

    runner.stubs(:wringer_client).returns(stub(fetch: fake_result))

    runner.run("url='http://example.local/events/1'")

    trace = tracer.to_h
    step = trace.find { |s| s[:wringer].is_a?(Hash) }

    assert_equal 123, step[:wringer][:duration_ms]
  end

  test "trace includes wringer final_url and redirect_chain" do
    runner, tracer = build_runner

    fake_result = {
      body: "<html>ok</html>",
      wringer: {
        error_type: nil,
        signals: {},
        hints: [],
        final_url: "https://final.example.com",
        redirect_chain: ["http://start", "https://final.example.com"]
      },
      duration_ms: 50
    }

    runner.stubs(:wringer_client).returns(stub(fetch: fake_result))

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
    runner, tracer = build_runner
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
    runner, tracer = build_runner
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
    assert_match(/step: \"url\"/, events.second[:error_message].to_s)
  end

  test "non trace runner aborts on nil resolved url and does not reuse previous page state" do
    ctx = {
      url: "http://example.local",
      render_js: false,
      scrape_options: {},
      tracer: Dsl::DslNullTracer.new
    }
    runner = Dsl::DslAlgorithmRunner.new(ctx)
    runner.stubs(:safe_wringer_call).returns("<html><body><h1>Fresh</h1></body></html>")
    runner.expects(:execute_xpath).never

    result = runner.run("url='http://example.local/page';url=nil;xpath=//h1/text()")

    assert_equal "abort_update", result.first
    assert_equal "InvalidURL", result.last[:error_type]
    assert_equal "url", result.last[:step]
    assert_equal "dsl_runner", result.last[:source]
  end

  test "ensure_page abort stops pipeline without raising and prevents downstream ruby" do
    runner, tracer = build_runner
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
    runner, = build_runner
    runner.stubs(:safe_wringer_call).returns(
      ["abort_update", { error: "Wringer unreachable", error_type: "SocketError", source: "wringer" }]
    )

    result = runner.run("xpath=//h1/text()")

    assert_equal "abort_update", result.first
    assert_equal "wringer", result.last[:source]
    assert_equal "xpath", result.last[:step]
  end

  test "resolve_url_only nil URL aborts in api step without silent continuation" do
    runner, tracer = build_runner

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

    non_trace_runner = Dsl::DslAlgorithmRunner.new(
      url: "http://example.local",
      render_js: false,
      scrape_options: {},
      tracer: Dsl::DslNullTracer.new
    )
    non_trace_result = non_trace_runner.run("api=nil")

    assert_equal trace_result, non_trace_result
    assert_equal "abort_update", trace_result.first
    assert_equal "dsl_runner", trace_result.last[:source]
  end

  test "trace events always include wringer signals and hints keys" do
    runner, tracer = build_runner
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
    source = File.read(Rails.root.join("app/services/dsl/dsl_algorithm_runner.rb"))

    refute_match(/def\s+ok\(/, source)
    refute_match(/def\s+abort\(/, source)
    refute_match(/\[:abort,/, source)
  end

  test "xpath probe runs only when xpath is empty after url step" do
    html = "<html><head><title>Probe Title</title></head><body><p>body</p></body></html>"
    stub_request(:get, /localhost:3009\/websites\/wring/).to_return(status: 200, body: html)

    runner, tracer = build_runner
    result = runner.run("url='http://example.local/events/1';xpath=//h1/text()")

    assert_equal [], result

    url_event = tracer.to_h.first
    xpath_event = tracer.to_h.second

    assert_equal true, url_event.dig(:probe, :skipped)
    assert_equal "//title", xpath_event.dig(:probe, :result, :xpath)
    assert_equal ["Probe Title"], xpath_event.dig(:probe, :result, :output)
  end

  test "xpath probe does not run for empty xpath when previous step is not url" do
    html = "<html><head><title>Probe Title</title></head><body><p>body</p></body></html>"
    stub_request(:get, /localhost:3009\/websites\/wring/).to_return(status: 200, body: html)

    runner, tracer = build_runner
    result = runner.run("xpath=//h1/text()")

    assert_equal [], result
    assert_equal true, tracer.to_h.first.dig(:probe, :skipped)
  end

  test "xpath probe is attached only to first empty xpath after url" do
    html = "<html><head><title>Probe Title</title></head><body><p>body</p></body></html>"
    stub_request(:get, /localhost:3009\/websites\/wring/).to_return(status: 200, body: html)

    runner, tracer = build_runner
    result = runner.run("url='http://example.local/events/1';xpath=//h1/text();xpath=//h2/text()")

    assert_equal [], result

    events = tracer.to_h
    assert_equal true, events.first.dig(:probe, :skipped)
    assert_equal "//title", events.second.dig(:probe, :result, :xpath)
    assert_equal true, events.third.dig(:probe, :skipped)
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
    html = "<html><head><title>Probe Title</title></head><body><p>body</p></body></html>"
    stub_request(:get, /localhost:3009\/websites\/wring/).to_return(status: 200, body: html)

    runner, tracer = build_runner
    result = runner.run("xpath=//h1/text();xpath=//h2/text()")

    assert_equal [], result
    assert_equal true, tracer.to_h.first.dig(:probe, :skipped)
    assert_equal true, tracer.to_h.second.dig(:probe, :skipped)
  end

  test "xpath probe stays trace-only and does not change pipeline output" do
    html = "<html><head><title>SHOULD_NOT_REPLACE_OUTPUT</title></head><body><p>body</p></body></html>"
    stub_request(:get, /localhost:3009\/websites\/wring/).to_return(status: 200, body: html)

    runner, tracer = build_runner

    result = runner.run("url='http://example.local/events/1';xpath=//h1/text()")
    probe_output = tracer.to_h.second.dig(:probe, :result, :output)

    assert_equal [], result
    assert_equal ["SHOULD_NOT_REPLACE_OUTPUT"], probe_output
    refute_equal probe_output, result
  end
end
