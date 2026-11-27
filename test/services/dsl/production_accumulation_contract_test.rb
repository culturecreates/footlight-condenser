require "test_helper"
require "ostruct"

class Dsl::ProductionAccumulationContractTest < ActiveSupport::TestCase
  include DslRunnerTestHelper

  setup { expect_no_fetch_seams }

  test "XPath CSS and conditional XPath append exact text including empty slots and whitespace" do
    html = "<p>  first\n line </p><p></p><b> B </b><i></i>"
    algorithm = "xpath=//p;css=b;if_xpath=//i"
    expected = ["  first\n line ", "", " B ", ""]
    [Dsl::Tracing::NullTracer.new, Dsl::Tracing::TraceCollector.new].each do |tracer|
      runner, = build_runner_with_html(html: html, tracer: tracer)
      assert_equal expected, runner.run(algorithm)
    end
  end

  test "nested saved data stays isolated until Ruby explicitly drops or replaces it" do
    runner, tracer = build_runner_with_html(html: "<p>Regular</p><p>Student</p><b>Available</b>")
    algorithm = "xpath=//p;ruby=[$array];xpath=//b;ruby=$array.drop(1)"
    assert_equal ["Available"], runner.run(algorithm)
    assert_equal [["Regular", "Student"]], tracer.to_h[1][:output_full]
    assert_equal [["Regular", "Student"], "Available"], tracer.to_h[2][:output_full]
    assert_equal ["Regular", "Student"], tracer.to_h[0][:output_full]
  end

  test "sanitized extraction appends HTML without flattening the previously saved array" do
    runner, = build_runner_with_html(html: '<p><strong>Keep</strong></p>')
    assert_equal [["saved"], '<p><strong>Keep</strong></p>'], runner.run('ruby=[["saved"]];xpath_sanitize=//p')
  end

  test "JSON appends evaluated arrays as nested values and retains explicit nil results" do
    runner, = build_runner_with_text(text: '{"values":["a","b"],"number":3}')
    result = runner.run('ruby=["seed"];json=$json["values"];json=$json["number"];json=$json["missing"]')
    assert_equal ["seed", ["a", "b"], 3, nil], result
  end

  test "each JSON instruction reparses the current input as production does" do
    runner, = build_runner_with_text(text: '{"number":3}')
    result = runner.run('json=$json["number"];ruby=$json["number"]=8' + "\n$array" + ';json=$json["number"]')
    assert_equal [3, 3], result
  end

  test "time zone appends without erasing earlier extracted values" do
    runner, = build_runner_with_html(html: "<time>2027-01-01</time>")
    assert_equal ["2027-01-01", "time_zone: UTC"], runner.run("xpath=//time;time_zone=UTC")
  end

  test "SPARQL appends then flattens the full result array as production does" do
    runner, = build_runner_with_html
    runner.instance_variable_set(:@graph, RDF::Graph.new)
    rows = %w[a b].map { |value| OpenStruct.new(answer: OpenStruct.new(value: value)) }
    SPARQL.expects(:execute).returns(rows)
    assert_equal %w[saved a b], runner.run('ruby=[["saved"]];sparql={?s schema:name ?answer}')
  end

  test "ordinary statement entry point executes instructions following a leading SPARQL step" do
    runner, = build_runner_with_html
    runner.instance_variable_set(:@graph, RDF::Graph.new)
    SPARQL.expects(:execute).returns([OpenStruct.new(answer: OpenStruct.new(value: "event"))])
    Dsl::Core::AlgorithmRunner.expects(:new).returns(runner)
    proxy = StatementsHelper.build_refresh_proxy(cookies: {})
    assert_equal ["EVENT"], proxy.process_algorithm(algorithm: 'sparql={?s schema:name ?answer};ruby=$array.map(&:upcase)', url: "https://example.org/event")
  end

  test "condition halts preserve the results collected before the condition" do
    ["if_xpath=//missing", "unless_xpath=//p"].each do |condition|
      runner, = build_runner_with_html(html: "<p>keep</p>")
      assert_equal ["keep"], runner.run("xpath=//p;#{condition};ruby=raise 'must not execute'")
    end
  end

  test "Ruby may deliberately replace results with nil or an empty array" do
    runner, = build_runner_with_html(html: "<p>discard</p><b>keep</b>")
    assert_nil runner.run("xpath=//p;ruby=nil")
    assert_equal ["keep"], runner.run("xpath=//p;ruby=[];xpath=//b")
  end

  test "navigation preserves accumulated values and empty XPath probes inspect only the new match set" do
    runner, tracer = build_runner_with_html(html: "<p>keep</p>")
    runner.stubs(:resolve_and_fetch_url).returns("<title>New page</title>")
    result = runner.run("xpath=//p;url='https://example.org/other';xpath=//missing")
    assert_equal ["keep"], result
    assert_equal ["New page"], tracer.to_h.last.dig(:probe, :result, :output)
    assert_equal ["keep"], tracer.to_h.first[:output_full]
  end

  test "pre-restoration fingerprints cannot certify the corrected interpreter contract" do
    website = websites(:one)
    old_inputs = ["fresh_both_v1", website.attributes.slice("seedurl", "default_language", "graph_name"),
      website.sources.order(:id).pluck(*Source.column_names),
      Property.where(id: website.sources.select(:property_id)).order(:id).pluck(*Property.column_names),
      RdfsClass.order(:id).pluck(:id, :name), website.webpages.order(:id).pluck(*Webpage.column_names)]
    assert_not_equal Digest::SHA256.hexdigest(JSON.generate(old_inputs)), Distillator::TransitionFingerprint.call(website)
    assert_equal "production_append_v1", Dsl::Core::AlgorithmRunner::CONTRACT_VERSION
  end
end
