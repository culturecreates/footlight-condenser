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
