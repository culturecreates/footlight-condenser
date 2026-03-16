require "test_helper"
require "webmock/minitest"

class DslAlgorithmRunnerTest < ActiveSupport::TestCase

  #
  # WebMock setup
  #
  setup do
    # Block all real HTTP unless explicitly stubbed
    stub_request(:get, /.*/).to_return(status: 200, body: "", headers: {})
  end

  #
  # Test helper to build runner + tracer
  #
  def build_runner(start_url = "http://example.local")
    tracer = Dsl::DslTraceCollector.new
    ctx = {
      url: start_url,
      render_js: false,
      scrape_options: {},
      tracer: tracer
    }
    [DslAlgorithmRunner.new(ctx), tracer]
  end

  #
  # Simple prefix tests
  #

  test "xpath prefix extracts text from HTML" do
    html = "<html><body><p>Hello World</p></body></html>"
    stub_request(:get, /wringer.*uri=http.*example.local/)
      .to_return(status: 200, body: html)

    runner, = build_runner("http://example.local")
    result = runner.run("xpath=//p/text()")

    assert_equal ["Hello World"], result
  end

  test "css prefix extracts text from HTML" do
    html = "<html><body><span class='x'>Foo</span></body></html>"
    stub_request(:get, /wringer.*uri=http.*example.local/)
      .to_return(status: 200, body: html)

    runner, = build_runner("http://example.local")
    result = runner.run("css=.x")

    assert_equal ["Foo"], result
  end

  #
  # URL changing behavior
  #

  test "url prefix updates runner url and used in next xpath" do
    html_home = "<html><body><a href='http://example.local/page'>Link</a></body></html>"
    html_page = "<html><body><h1>Title</h1></body></html>"

    stub_request(:get, /wringer.*uri=http.*example.local/)
      .to_return(status: 200, body: html_home)
    stub_request(:get, /wringer.*uri=http.*example.local/)
      .to_return(status: 200, body: html_page)

    runner, = build_runner("http://example.local")
    algo = "xpath=//a/@href; url=$array.first; xpath=//h1/text()"
    result = runner.run(algo)

    assert_equal ["Title"], result
  end

  test "renderjs_url uses stubbed page (js rendered)" do
    js_html = "<html><body><div id='x'>Rendered</div></body></html>"
    # Wringer call will contain escaped URI
    stub_request(:get, /footlight-wringer.*uri=http.*example.local/)
      .to_return(status: 200, body: js_html)

    runner, = build_runner("http://example.local")
    algo = "renderjs_url=$url; xpath=//div[@id='x']/text()"
    result = runner.run(algo)

    assert_equal ["Rendered"], result
  end

  #
  # JSON prefix behavior
  #

  test "json prefix loads JSON and returns value" do
    json_body = { "foo" => "bar" }.to_json
    stub_request(:get, /footlight-wringer.*uri=http.*example.local/)
      .to_return(status: 200, body: json_body)

    runner, = build_runner("http://example.local")
    result = runner.run("json=$json['foo']")

    assert_equal "bar", result
  end

  #
  # Ruby prefix behavior
  #

  test "ruby prefix can manipulate array via lambda" do
    html = "<html><body><p>a</p><p>b</p></body></html>"
    stub_request(:get, /wringer.*uri=http.*example.local/)
      .to_return(status: 200, body: html)

    runner, = build_runner("http://example.local")
    algo = <<~DSL
      xpath=//p/text();
      ruby=$array.map(&:upcase)
    DSL

    result = runner.run(algo)
    assert_equal %w[A B], result
  end

  #
  # Abort and invalid URL tests
  #

  test "abort if renderjs_url has no valid URL in $array" do
    runner, tracer = build_runner("http://example.local")
    result = runner.run("renderjs_url=$array.first")

    assert_equal "abort_update", result.first
    assert_match(/Invalid URL/, result.last[:error])

    found = tracer.to_h[:events].any? do |evt|
      evt.is_a?(Hash) && evt[:error].to_s.include?("Invalid URL")
    end
    assert found
  end

  test "abort if url prefix gets invalid string" do
    runner, tracer = build_runner("http://example.local")
    result = runner.run("url=$array.first")

    assert_equal "abort_update", result.first
    assert_match(/Invalid URL/, result.last[:error])

    found = tracer.to_h[:events].any? do |evt|
      evt.is_a?(Hash) && evt[:error].to_s.include?("Invalid URL")
    end
    assert found
  end

  #
  # if_xpath / unless_xpath behavior
  #

  test "if_xpath returns nodes when match present" do
    html = "<html><body><item>OK</item></body></html>"
    stub_request(:get, /wringer.*uri=http.*example.local/)
      .to_return(status: 200, body: html)

    runner, = build_runner("http://example.local")
    result = runner.run("if_xpath=//item; xpath=//item/text()")

    assert_equal ["OK"], result
  end

  test "unless_xpath breaks when expression matches" do
    html = "<html><body><h1>Y</h1></body></html>"
    stub_request(:get, /wringer.*uri=http.*example.local/)
      .to_return(status: 200, body: html)

    runner, = build_runner("http://example.local")
    result = runner.run("unless_xpath=//h1; xpath=//h1/text()")

    assert_empty result
  end

  #
  # time_zone prefix
  #

  test "time_zone prefix returns time zone array" do
    runner, = build_runner("http://example.local")
    result = runner.run("time_zone=UTC")

    assert_equal ["time_zone: UTC"], result
  end

  #
  # Sparql prefix should abort when no RDF available
  #

  test "sparql prefix returns abort if graph not present" do
    runner, = build_runner("http://example.local")
    result = runner.run("sparql={?s ?p ?o}")

    assert_equal "abort_update", result.first
  end
end