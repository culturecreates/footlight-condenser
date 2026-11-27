require "test_helper"
require Rails.root.join("script/databus_replay")

class Dsl::RdfGraphLoadingTest < ActiveSupport::TestCase
  include DslRunnerTestHelper

  setup do
    @url = "https://www.placedesarts.com/evenement/5-7-musicaux-avec-udm"
    # Reproduce the extensionless HTML response: its first 1 KB has no RDF
    # markers, while structured event data appears further into the document.
    @html = '<!DOCTYPE html><html lang="fr-CA"><head><meta charset="UTF-8"><!--' + ("head padding " * 130) + '-->' + <<~HTML
      <script type="application/ld+json">
      {"@context":{"schema":"http://schema.org/"},"@type":"schema:Event",
       "@id":"#{@url}#event","schema:eventStatus":{"@id":"schema:EventScheduled"},
       "schema:eventAttendanceMode":{"@id":"schema:OfflineEventAttendanceMode"},
       "schema:endDate":{"@value":"2027-02-06T18:30:00-05:00","@type":"http://www.w3.org/2001/XMLSchema#dateTime"}}
      </script></head><body><h1>5 à 7 musicaux</h1></body></html>
    HTML
    @expected = { "eventStatus" => "http://schema.org/EventScheduled",
      "eventAttendanceMode" => "http://schema.org/OfflineEventAttendanceMode", "endDate" => "2027-02-06T18:30:00-05:00" }
  end

  test "ordinary runner extracts the three Place des Arts SPARQL fields from HTML without MIME metadata" do
    fetch = distillator_fetch_response(body: @html, html: @html, headers: {}, final_url: @url)
    Distillator::FetchCacheStore.expects(:fetch).times(3).returns(fetch)
    @expected.each do |property, expected|
      runner, = build_runner(url: @url)
      assert_equal [expected], runner.run("sparql={?s a schema:Event. ?s schema:#{property} ?answer}")
    end
  end

  test "cache-only replay extracts those same fields without fetching or changing the HTML" do
    reader = mock("recorded Wringer input")
    reader.expects(:fetch).with(@url).times(3).returns(@html)
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    @expected.each do |property, expected|
      runner = Distillator::DatabusReplay::CacheRunner.new(
        { url: @url, render_js: false, scrape_options: {}, tracer: Dsl::Tracing::NullTracer.new }, reader: reader)
      assert_equal [expected], runner.run("sparql={?s a schema:Event. ?s schema:#{property} ?answer}")
    end
  end

  test "declared HTML MIME produces the same extracted RDF values" do
    fetch = distillator_fetch_response(body: @html, html: @html, headers: { "Content-Type" => "text/html; charset=UTF-8" }, final_url: @url)
    Distillator::FetchCacheStore.expects(:fetch).returns(fetch)
    runner, = build_runner(url: @url)
    assert_equal [@expected["eventStatus"]], runner.run("sparql={?s a schema:Event. ?s schema:eventStatus ?answer}")
  end

  test "bare HTML root also supports RDFa properties beyond the format-detection sample" do
    html = "  <HTML><head><!--#{'padding ' * 180}--></head>" \
      '<body vocab="http://schema.org/" typeof="Event"><span property="eventStatus" resource="http://schema.org/EventCancelled"></span></body></HTML>'
    fetch = distillator_fetch_response(body: html, headers: {}, final_url: @url)
    Distillator::FetchCacheStore.expects(:fetch).returns(fetch)
    runner, = build_runner(url: @url)
    assert_equal ["http://schema.org/EventCancelled"], runner.run("sparql={?s a schema:Event. ?s schema:eventStatus ?answer}")
  end

  test "explicit lower-case header MIME is not overwritten by HTML inference" do
    fetch = distillator_fetch_response(body: @html, headers: { "content-type" => "application/octet-stream" }, final_url: @url)
    Distillator::FetchCacheStore.expects(:fetch).returns(fetch)
    runner, = build_runner(url: @url)
    result = runner.run("sparql={?s a schema:Event. ?s schema:eventStatus ?answer}")
    assert_equal "abort_update", result.first
    assert_equal "RDF::FormatError", result.last[:error_type]
  end

  test "Turtle input and explicit MIME retain their normal RDF parsing behavior" do
    ttl = '@prefix schema: <http://schema.org/> . <https://example.org/event> a schema:Event; schema:eventStatus schema:EventScheduled .'
    [{}, { content_type: "text/turtle; charset=UTF-8" }].each do |headers|
      fetch = distillator_fetch_response(body: ttl, headers: headers, final_url: @url)
      Distillator::FetchCacheStore.expects(:fetch).returns(fetch)
      runner, = build_runner(url: @url)
      assert_equal [@expected["eventStatus"]], runner.run("sparql={?s a schema:Event. ?s schema:eventStatus ?answer}")
    end
  end

  test "recognizing HTML does not invent an answer when the event RDF is absent" do
    fetch = distillator_fetch_response(body: "<!DOCTYPE html><html><body><h1>Ordinary page without event data</h1></body></html>", headers: {}, final_url: @url)
    Distillator::FetchCacheStore.expects(:fetch).returns(fetch)
    runner, = build_runner(url: @url)
    assert_equal [], runner.run("sparql={?s a schema:Event. ?s schema:eventStatus ?answer}")
  end
end
