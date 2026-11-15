require "test_helper"

class EventSeriesExportSafetyTest < ActiveSupport::TestCase
  EVENT_URI = "http://kg.footlight.io/resource/culturemauricie_lepointdevente-com_partytime2026".freeze

  test "six dates and fifteen location values raise an actionable error without discarding input" do
    graph = event_graph(locations: 15)
    before = graph.to_a

    error = assert_raises(JsonldGenerator::EventSeriesConversionError) do
      JsonldGenerator.make_event_series(graph, EVENT_URI)
    end

    assert_equal EVENT_URI, error.rdf_uri
    assert_equal 6, error.start_dates
    assert_equal 0, error.end_dates
    assert_equal 15, error.locations
    assert_includes error.message, "one shared location or one location per start date"
    assert_equal before, graph.to_a
  end

  test "six dates at one shared venue retain every performance" do
    graph = JsonldGenerator.make_event_series(event_graph(locations: 1), EVENT_URI)
    assert graph.has_statement?(RDF::Statement(RDF::URI(EVENT_URI), RDF.type, RDF::URI("http://schema.org/EventSeries")))
    children = graph.query([RDF::URI(EVENT_URI), RDF::URI("http://schema.org/subEvent"), nil]).map(&:object)
    assert_equal 6, children.uniq.count
    children.each do |child|
      assert_equal 1, graph.query([child, RDF::URI("http://schema.org/startDate"), nil]).count
      assert_equal [RDF::URI("https://example.org/venue/0")], graph.query([child, RDF::URI("http://schema.org/location"), nil]).map(&:object)
    end
  end

  test "SPARQL failures cannot be swallowed into an apparently successful export" do
    graph = event_graph(locations: 1)
    RdfLoader.stubs(:load_sparql).returns("not a SPARQL update")
    error = assert_raises(JsonldGenerator::EventSeriesConversionError) do
      JsonldGenerator.make_event_series(graph, EVENT_URI)
    end
    assert_includes error.message, "EventSeries transformation failed"
    assert_equal 6, error.start_dates
    assert_not_nil error.cause
  end

  test "invalid EventSeries stops Databus publication before S3 upload or registration" do
    graph = event_graph(locations: 15)
    EventsController.any_instance.stubs(:publishable_events).returns([EVENT_URI])
    JsonldGenerator.stubs(:load_all_statements).returns(EVENT_URI => [])
    JsonldGenerator.stubs(:build_graph).returns(graph)
    ExportGraphToDatabus.expects(:save_on_s3).never
    ExportGraphToDatabus.expects(:add_to_databus).never

    assert_raises(JsonldGenerator::EventSeriesConversionError) do
      ExportGraphToDatabus.export_events("culturemauricie_lepointdevente-com", "https://fixtures.example")
    end
  end

  private

  # Reproduce the reported cardinalities through the real RDF-star builder.
  # These are synthetic venue candidates, not assertions about their identities.
  def event_graph(locations:)
    base = { subject: EVENT_URI, webpage_class_name: "Event", rdfs_class_name: "Event", language: "" }
    dates = 6.times.map { |index| "2026-12-#{(index + 10).to_s.rjust(2, '0')}T20:00:00-05:00" }
    values = ["Extracted venue", "Place"] + locations.times.map { |index| ["Candidate #{index}", "https://example.org/venue/#{index}"] }
    JsonldGenerator.build_graph([
      base.merge(predicate: "http://schema.org/startDate", datatype: "xsd:dateTime", value: dates.to_json),
      base.merge(predicate: "http://schema.org/location", datatype: "xsd:anyURI", value: values.to_json),
      base.merge(predicate: "http://schema.org/name", datatype: "xsd:string", value: "Partytime")
    ], for_artsdata: true)
  end
end
