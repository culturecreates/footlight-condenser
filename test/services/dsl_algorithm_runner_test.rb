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
end
