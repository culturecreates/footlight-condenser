require "test_helper"
require "ostruct"

class Dsl::HistoricalAccumulationDifferentialTest < ActiveSupport::TestCase
  include DslRunnerTestHelper

  # Keep the old evaluator independent of AlgorithmRunner. Only I/O and view
  # dependencies are supplied here; the production method itself is verbatim.
  class HistoricalEvaluator
    Page = Struct.new(:text)
    class_eval File.read(File.expand_path("../../fixtures/dsl/historical_process_algorithm.rb.fixture", __dir__)), __FILE__

    def logger = Rails.logger
    def use_wringer(url, *) = url
    def safe_wringer_call = yield
    def sanitize(...) = ApplicationController.helpers.sanitize(...)
  end

  START = "https://example.org/event".freeze

  setup { expect_no_fetch_seams }

  test "FASS source 219 retains all four CSS groups before pairing dates" do
    html = '<table><tr><td class="tableCell1_oo">November 20</td><td class="tableCell1_oo">20:00</td></tr>' \
      '<tr><td class="tableCell1_oe">November 21</td><td class="tableCell1_oe">19:00</td></tr></table>'
    algorithm = "css=.tableCell1_oo:nth-child(1);css=.tableCell1_oo:nth-child(2);" \
      "css=.tableCell1_oe:nth-child(1);css=.tableCell1_oe:nth-child(2);" \
      "ruby=$array.each_slice(2).map {|n| n.first + ' ' + n.second}"
    assert_differential algorithm, html: html, expected: ["November 20 20:00", "November 21 19:00"]
  end

  test "Vieux Noranda source 1716 retains dates through timezone and datetime formatting" do
    html = '<script type="application/ld+json">{}</script>' \
      '<script type="application/ld+json">[]</script>' \
      '<script type="application/ld+json">[{"startDate":"2026-11-20T20:00:00+00:00"}]</script>'
    algorithm = "xpath=//script[@type='application/ld+json'];" \
      "ruby=JSON.parse($array[2]).map{|s| s['startDate'].chomp('+00:00')};time_zone=Eastern Time (US & Canada)"
    raw = ["2026-11-20T20:00:00", "time_zone: Eastern Time (US & Canada)"]
    outputs = assert_differential algorithm, html: html, expected: raw
    formatter = StatementsHelper.build_refresh_proxy(cookies: {})
    outputs.each do |output|
      assert_equal ["2026-11-20T20:00:00-05:00"], formatter.convert_datetime(output.deep_dup)
      assert_equal "2026-11-20T20:00:00-05:00", formatter.format_datatype(output.deep_dup, properties(:ten), webpages(:one))
    end
  end

  test "unchanged Joliette source 7023 agrees with the old evaluator on sold out and available inputs" do
    algorithm = Rails.root.join("test/fixtures/dsl/joliette/original_availability.dsl").read.split(";").map(&:strip).join(";")
    { "sold_out" => %w[SoldOut SoldOut SoldOut SoldOut], "available" => %w[InStock SoldOut SoldOut] }.each do |name, statuses|
      assert_differential algorithm, html: Rails.root.join("test/fixtures/dsl/joliette/#{name}.html").read,
        expected: statuses.map { |status| "http://schema.org/#{status}" }
    end
  end

  test "headings paragraphs parallel link arrays and nested drop patterns retain order and types" do
    html = '<h2> Heading </h2><p> Paragraph </p><a href="/a">A</a><a href="/b">B</a><i></i>'
    assert_differential 'xpath=//h2;xpath=//p', html: html, expected: [" Heading ", " Paragraph "]
    assert_differential 'xpath=//a;xpath=//a/@href;ruby=$array.each_slice($array.count/2).to_a.transpose',
      html: html, expected: [["A", "/a"], ["B", "/b"]]
    assert_differential 'xpath=//h2;ruby=[$array];xpath=//p;ruby=$array.drop(1)', html: html, expected: [" Paragraph "]
    assert_differential 'xpath=//i;css=p;if_xpath=//h2', html: html, expected: ["", " Paragraph ", " Heading "]
    assert_differential 'ruby=[["saved"]];xpath_sanitize=//p', html: html, expected: [["saved"], "<p> Paragraph </p>\n"]
  end

  test "pagination keeps prior page dates while appending the second page" do
    html = '<time>2026-11-20</time><a rel="next" href="https://example.org/next">Next</a>'
    assert_differential 'xpath=//time;ruby=[$array];xpath=//a/@href;url=$array.last;ruby=$array.take(1).flatten;xpath=//time',
      html: html, pages: { "https://example.org/next" => '<time>2026-11-21</time>' }, expected: %w[2026-11-20 2026-11-21]
  end

  test "JSON appends arrays scalars and nil and reparses current input" do
    html = '{"venue":["A","B"],"ticket":"/buy"}'
    assert_differential 'json=$json["venue"];json=$json["ticket"];json=$json["missing"]',
      html: html, expected: [["A", "B"], "/buy", nil]
    assert_differential 'json=$json["ticket"];ruby=$json["ticket"]="changed"' + "\n$array" + ';json=$json["ticket"]',
      html: html, expected: ["/buy", "/buy"]
  end

  test "unchanged Culture Mauricie price 7870 agrees with the historical evaluator on identical rates inputs" do
    algorithm = Rails.root.join("test/fixtures/dsl/culture_mauricie_price.dsl").read.split(";").map(&:strip).join(";")
    html = '<html><body data-reference="fixture-rates"><ul class="performances">' \
      '<li><a href="/billets/performance">Performance</a></li></ul></body></html>'
    # Representative JSON shapes, not claimed historical response snapshots.
    # Freeze all navigation inputs for both independent engines and tracing modes.
    [
      [[{ "price" => 37.74 }], [37.74]],
      [[{ "price" => 42.99 }, { "price" => nil }], [42.99]],
      [[{ "price" => 128.32 }, { "price" => 68.17 }], [128.32, 68.17]],
      [{ "price" => 42.99 }, [42.99]]
    ].each do |rates, expected|
      assert_differential algorithm, html: html, expected: expected,
        pages: { "https://lepointdevente.com/plugins/rates/fixture-rates" => { rates: rates }.to_json }
    end
  end

  test "Gatineau End Date 4264 has the same unreachable fallback in both evaluators and an unconditional XPath repairs it" do
    original = Rails.root.join("test/fixtures/dsl/gatineau_original_end_date.dsl").read.split(";").map(&:strip).join(";")
    patched = original.sub(";if_xpath=", ";xpath=")
    formatter = StatementsHelper.build_refresh_proxy(cookies: {})
    property = Property.new(label: "End Date", value_datatype: "xsd:dateTime")
    [
      ["Du mercredi 7 avril 2027 au dimanche 25 avril 2027", "dimanche 25 avril 2027", "2027-04-25"],
      ["Le jeudi 26 novembre 2026, de 16:00 à 18:00", "Le jeudi 26 novembre 2026, 18:00", "2026-11-26T18:00:00-05:00"]
    ].each do |occurrence, fallback, expected|
      html = gatineau_occurrence_html(occurrence)
      assert_differential original, html: html, expected: [[fallback]]
      assert_differential(patched, html: html, expected: [fallback]).each do |raw|
        assert_equal expected, formatter.format_datatype(raw.deep_dup, property, webpages(:one))
      end
    end

    # A successful AddEvent lookup retains its existing priority and conversion.
    html = gatineau_occurrence_html("Du mercredi 7 avril 2027 au dimanche 25 avril 2027", end_value: "04-24-2027 23:00")
    [original, patched].each { |algorithm| assert_differential algorithm, html: html, expected: ["2027-04-24"] }

    # No end date remains blank; the repair must not invent one from a start time.
    html = gatineau_occurrence_html("Le jeudi 26 novembre 2026 à 16:00")
    assert_differential original, html: html, expected: [[""]]
    assert_differential(patched, html: html, expected: [""]).each do |raw|
      assert_equal "", formatter.format_datatype(raw.deep_dup, property, webpages(:one))
    end
  end

  test "SPARQL accumulation and flattening agree with the independent evaluator" do
    RDF::Graph.stubs(:load).returns(RDF::Graph.new)
    rows = %w[a b].map { |value| OpenStruct.new(answer: OpenStruct.new(value: value)) }
    SPARQL.stubs(:execute).returns(rows)
    assert_differential 'ruby=[["saved"]];sparql={?s schema:name ?answer}', html: "", expected: %w[saved a b]
  end

  test "conditional halts and explicit Ruby replacement preserve the original result contract" do
    html = '<p>keep</p><b>new</b>'
    ["if_xpath=//missing", "unless_xpath=//p"].each do |condition|
      assert_differential "xpath=//p;#{condition};ruby=raise 'must not execute'", html: html, expected: ["keep"]
    end
    assert_differential 'xpath=//p;ruby=[];xpath=//b', html: html, expected: ["new"]
    assert_differential 'xpath=//p;ruby=nil', html: html, expected: nil
    assert_differential 'xpath=//p;ruby=$array.uniq!', html: html, expected: nil
  end

  test "accumulation preserves Ruby object behavior rather than coercing to arrays" do
    assert_differential 'ruby="prefix";xpath=//p', html: '<p> suffix</p>', expected: "prefix suffix"
    ['ruby=nil;xpath=//p', 'ruby={};css=p', 'ruby=7;time_zone=UTC', 'ruby=["a"];ruby=$array.drop(nil)'].each do |algorithm|
      assert_differential_error algorithm, html: '<p>value</p>'
    end
  end

  private

  def gatineau_occurrence_html(text, end_value: nil)
    ending = end_value ? "<span class='addeventatc'><span class='end'>#{end_value}</span></span>" : ""
    "<div class='desktop'><div class='occurrences'><ul><li><span class='occurrence'>" \
      "<span class='date-heure'>#{text}</span></span></li></ul></div>#{ending}</div>"
  end

  def legacy_result(algorithm, pages)
    agent = Object.new
    agent.define_singleton_method(:user_agent_alias=) { |_| }
    agent.define_singleton_method(:get_file) { |url| pages.fetch(url) }
    Mechanize.stubs(:new).returns(agent)
    HistoricalEvaluator.new.process_algorithm(algorithm: algorithm, url: START)
  ensure
    Mechanize.unstub(:new)
  end

  def corrected_results(algorithm, pages)
    [Dsl::Tracing::NullTracer.new, Dsl::Tracing::TraceCollector.new].map do |tracer|
      runner, = build_runner(url: START, tracer: tracer)
      runner.instance_variable_set(:@graph, RDF::Graph.new) if algorithm.include?("sparql=")
      runner.define_singleton_method(:fetch_result_for) do |**args|
        { status: :ok, body: pages.fetch(args[:url]) }
      end
      runner.run(algorithm)
    end
  end

  def shape(value)
    [value.class.name, case value
    when Array then value.map { |item| shape(item) }
    when Hash then value.map { |key, item| [shape(key), shape(item)] }
    end]
  end

  def assert_differential(algorithm, html:, expected:, pages: {})
    pages = { START => html }.merge(pages)
    legacy = legacy_result(algorithm, pages)
    assert_equal expected, legacy
    corrected = corrected_results(algorithm, pages)
    corrected.each do |actual|
      assert_equal legacy, actual
      assert_equal shape(legacy), shape(actual)
    end
    [legacy, *corrected]
  end

  def assert_differential_error(algorithm, html:)
    pages = { START => html }
    legacy = legacy_result(algorithm, pages)
    assert_equal "abort_update", legacy.first
    corrected_results(algorithm, pages).each do |actual|
      assert_equal "abort_update", actual.first
      assert_equal legacy.last[:error_type].to_s, actual.last[:error_type]
      assert_equal legacy.last[:algorithm_rescued].partition("=").first, actual.last[:step]
    end
  end
end
