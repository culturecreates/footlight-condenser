require "test_helper"
require "webmock/minitest"

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
    Thread.current.delete(:dsl_array)
    Thread.current.delete(:dsl_url)
    Thread.current.delete(:dsl_json)
  end
end
