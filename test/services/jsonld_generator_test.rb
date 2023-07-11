require 'test_helper'

class JsonldGeneratorTest < ActiveSupport::TestCase
  include ResourcesHelper
  include JsonUtilities

  # test method build_graph
  test "build_graph" do
    statements = [statements(:three)].map { |stat| adjust_labels_for_api(stat, subject: "http://subject.com") }
    nesting_options = {}
    expected_output = 7
    assert_equal expected_output, JsonldGenerator.build_graph(statements, nesting_options).count
  end

  ############################
  # test make_event_series
  ############################

  test "count_locations" do
    g =  RDF::Graph.load("test/fixtures/files/event_2_places_input.ttls", format: :ttl, rdfstar: true)
    locations = JsonldGenerator.count_quoted_triples(g,'location')
    # puts actual.dump(:turtle, rdfstar: true)
    assert_equal 2, locations
  end

  test "count_repeating_locations" do
    g =  RDF::Graph.load("test/fixtures/files/event_4_places_input.ttls", format: :ttl, rdfstar: true)
    locations = JsonldGenerator.count_quoted_triples(g,'location')
    # puts actual.dump(:turtle, rdfstar: true)
    assert_equal 4, locations
  end

  test "basic graph" do 
    g =  RDF::Graph.load("test/fixtures/files/event_2_places_input.ttls", format: :ttl, rdfstar: true)
    # puts g.dump(:turtle, rdfstar: true)
    assert_equal 10, g.count
  end

  test "convert only startDates to subEvents" do
    g =  RDF::Graph.load("test/fixtures/files/event_2_dates_input.ttls", format: :ttl, rdfstar: true)
    expected_output = RDF::Graph.load("test/fixtures/files/event_2_dates_output.ttls", format: :ttl, rdfstar: true)
    actual = JsonldGenerator.make_event_series(g,"adr:spec-qc-ca_broue")

    # puts actual.dump(:turtle, rdfstar: true)
    assert_equal expected_output.count, actual.count
  end

  test "DO NOT convert single startDate to subEvents" do
    @schema = RDF::Vocabulary.new("http://schema.org/")
    g = RDF::Graph.new
    uri = RDF::URI.new("http://kg.artsdata.ca/resource/spec-qc-ca_broue")
    g << [uri, @schema.name, RDF::Literal.new("Test Event Series")]
    g << [uri, @schema.location, RDF::Literal.new("My Place")]
    g << [uri, @schema.startDate, RDF::Literal::DateTime.new("2020-07-14T08:00:00-04:00")]
    expected_output = g
    assert_equal expected_output.dump(:ntriples), JsonldGenerator.make_event_series(g,"http://kg.artsdata.ca/resource/spec-qc-ca_broue").dump(:ntriples)
  end

  test "convert 2 startDates and 2 endDates to subEvents" do
    g =  RDF::Graph.load("test/fixtures/files/event_2_end_dates_input.ttls", format: :ttl, rdfstar: true)
    expected_output = RDF::Graph.load("test/fixtures/files/event_2_end_dates_output.ttls", format: :ttl, rdfstar: true)
    actual = JsonldGenerator.make_event_series(g,"adr:spec-qc-ca_broue")

   #  pp JSON.parse(actual.dump(:jsonld, rdfstar: true))
    assert_equal expected_output.count, actual.count
  end

  test "convert 2 startDates and mismatched endDates to subEvents" do
    g =  RDF::Graph.load("test/fixtures/files/event_end_dates_mismatch_input.ttls", format: :ttl, rdfstar: true)
    expected_output = RDF::Graph.load("test/fixtures/files/event_end_dates_mismatch_output.ttls", format: :ttl, rdfstar: true)
    actual = JsonldGenerator.make_event_series(g,"adr:spec-qc-ca_broue")

   #  pp JSON.parse(actual.dump(:jsonld, rdfstar: true))
    assert_equal expected_output.count, actual.count
  end

  test "convert multiple locations only start dates to subEvents" do

    g =  RDF::Graph.load("test/fixtures/files/event_2_places_input.ttls", format: :ttl, rdfstar: true)
    expected_output = RDF::Graph.load("test/fixtures/files/event_2_places_output.ttls", format: :ttl, rdfstar: true)
    actual = JsonldGenerator.make_event_series(g,"adr:spec-qc-ca_broue")

    puts actual.dump(:turtle, rdfstar: true)
    assert_equal expected_output.count, actual.count
  end

  test "convert multiple locations to subEvents" do

    g =  RDF::Graph.load("test/fixtures/files/event_2_places_input.ttls", format: :ttl, rdfstar: true)
    expected_output = RDF::Graph.load("test/fixtures/files/event_2_places_output.ttls", format: :ttl, rdfstar: true)
    actual = JsonldGenerator.make_event_series(g,"adr:spec-qc-ca_broue")

    # puts actual.dump(:turtle, rdfstar: true)
    assert_equal expected_output.count, actual.count
  end

  test "convert 2 places 2 endDates to subEvents" do

    g =  RDF::Graph.load("test/fixtures/files/event_2_places_2_end_dates_input.ttls", format: :ttl, rdfstar: true)
    expected_output = RDF::Graph.load("test/fixtures/files/event_2_places_2_end_dates_output.ttls", format: :ttl, rdfstar: true)
    actual = JsonldGenerator.make_event_series(g,"adr:spec-qc-ca_broue")

    # puts actual.dump(:turtle, rdfstar: true)
    assert_equal expected_output.count, actual.count
  end


  test "convert 2 startDates on same day to subEvents" do

    g =  RDF::Graph.load("test/fixtures/files/event_2_dates_sameday_input.ttls", format: :ttl, rdfstar: true)
    expected_output = RDF::Graph.load("test/fixtures/files/event_2_dates_sameday_output.ttls", format: :ttl, rdfstar: true)
    actual = JsonldGenerator.make_event_series(g,"adr:spec-qc-ca_broue")

    puts actual.dump(:turtle, rdfstar: true)
    assert_equal expected_output.count, actual.count
  end

  ############################
  # test coalesce_language
  ############################
  setup do
    @schema = RDF::Vocabulary.new("http://schema.org/")
    @graph = RDF::Graph.new
    @graph << [:hello, @schema.name, RDF::Literal.new("My Theatre", language: :en)]
    @graph << [:hello, @schema.name, RDF::Literal.new("Mon Théâtre", language: :fr)]
    @graph << [:hello, @schema.name, RDF::Literal.new("Mien Théâtre")]
  end

  test "should return graph with no langauge tag preferred" do
    expected_output = RDF::Graph.new << [:hello, @schema.name,  RDF::Literal.new("Mien Théâtre")]
    assert_equal expected_output.dump(:ntriples), JsonldGenerator.coalesce_language(@graph).dump(:ntriples)
  end

  test "should return graph with @fr tag preferred" do 
    expected_output = RDF::Graph.new << [:hello, @schema.name,  RDF::Literal.new("Mon Théâtre", language: :fr)]
    assert_equal expected_output.dump(:ntriples), JsonldGenerator.coalesce_language(@graph, 'fr').dump(:ntriples)
  end

  test "should return graph with no langauge tag because @de is not available" do 
    expected_output = RDF::Graph.new << [:hello, @schema.name,  RDF::Literal.new("Mien Théâtre")]
    assert_equal expected_output.dump(:ntriples), JsonldGenerator.coalesce_language(@graph, 'de').dump(:ntriples)
  end

  test "should return graph with @fr langauge tag because @en is not available" do 
    graph = RDF::Graph.new << [:hello, @schema.name,  RDF::Literal.new("Mon Théâtre", language: :fr)]
    expected_output = RDF::Graph.new << [:hello, @schema.name,  RDF::Literal.new("Mon Théâtre", language: :fr)]
    assert_equal expected_output.dump(:ntriples), JsonldGenerator.coalesce_language(graph, 'en').dump(:ntriples)
  end

  test "should return graph with no change" do 
    graph = RDF::Graph.new << [:hello, @schema.image, RDF::Literal.new('http://my.image.com')]
    expected_output = RDF::Graph.new << [:hello, @schema.image,  RDF::Literal.new('http://my.image.com')]
    assert_equal expected_output.dump(:ntriples), JsonldGenerator.coalesce_language(graph, 'en').dump(:ntriples)
  end


  ############################
  # test extract_object_uris
  ############################

  test "should extract no URIs" do
    graph = RDF::Graph.new << [:hello, RDF::RDFS.label, "Hello, world!"]
    expected_output = []
    assert_equal expected_output, JsonldGenerator.extract_object_uris(graph)
  end

  test "should extract 2 URIs" do
    graph = RDF::Graph.new << [:hello, RDF::RDFS.label, RDF::URI.new("http://one.com")]
    graph << [:hello, RDF::RDFS.label, RDF::URI.new("http://two.com")]
    expected_output = [RDF::URI.new("http://two.com"),RDF::URI.new("http://one.com")].sort
    assert_equal expected_output, JsonldGenerator.extract_object_uris(graph).sort
  end

  # test method describe_uri
  test "should return graph" do
    uri = RDF::URI.new("http://kg.artsdata.ca/resource/K10-344")
    expected_output = 18
    assert_equal expected_output, JsonldGenerator.describe_uri(uri).count
  end

  test "should return graph for K12-170" do
    uri = RDF::URI.new("http://kg.artsdata.ca/resource/K12-170")
    expected_output = 9
    assert_equal expected_output, JsonldGenerator.describe_uri(uri).count
  end

  ############################
  # test dereferencing uri
  ############################
  test "should dereference artsdata uri" do
    uri = RDF::URI.new("http://kg.artsdata.ca/resource/K16-6") # Crossfire Productions
    expected_output = 11
    VCR.use_cassette('JsonldGenerator.dereference_uri artsdata') do
      actual = JsonldGenerator.dereference_uri(uri)
      assert_equal expected_output, actual.count
    end
  end

  test "should NOT dereference wikidata uri" do
    uri = RDF::URI.new("https://www.wikidata.org/entity/Q3308948")
    expected_output = 0
    actual = JsonldGenerator.dereference_uri(uri)
    assert_equal expected_output, actual.count
  end

  test "should not dereference when uri does not exist" do
    uri = RDF::URI.new("http://kg.artsdata.ca/resource/K16-677777777777")
    expected_output = 0
    VCR.use_cassette('JsonldGenerator.dereference_uri uri does not exist') do
      actual = JsonldGenerator.dereference_uri(uri)
      assert_equal expected_output, actual.count
    end
  end

  test "should not dereference invalid uri protocol" do
    uri = RDF::URI.new("ht://badprotocol.com")
    expected_output = 0
    actual = JsonldGenerator.dereference_uri(uri)
    assert_equal expected_output, actual.count
  end

  ############################
  # tests method delete_ids
  ############################
  test "should remove @ids" do
    jsonld = {"one" => "thing", "@id" => "123"}
    expected_output = {"one" => "thing"}
    assert_equal expected_output, JsonldGenerator.delete_ids(jsonld)
  end

  test "should remove all @ids" do
    jsonld = {"one" => "thing", "@id" => "123",  "organizer" =>  {
      "@id" => "http://kg.artsdata.ca/resource/K10-440", "name" => "organizer name"},
      "performer" =>  {"@id" => "http://kg.artsdata.ca/resource/K10-440"},
      "location" =>  {"@id" => "http://kg.artsdata.ca/resource/K10-440"}}
    expected_output = {"one" => "thing",  "organizer" =>  {"@id"=>"http://kg.artsdata.ca/resource/K10-440", "name" => "organizer name"}, "performer"=>{"@id"=>"http://kg.artsdata.ca/resource/K10-440"}, "location"=>{"@id"=>"http://kg.artsdata.ca/resource/K10-440"}}
    assert_equal expected_output, JsonldGenerator.delete_ids(jsonld)
  end

  test "should remove all @ids inside @graph and in list of performers" do
    jsonld = {'@graph' => [{"performer" => [ {"@id" => "http://kg.artsdata.ca/resource/K10-440", "name" => "K10-440"},{"@id" => "http://kg.artsdata.ca/resource/K10-441", "name" => "K10-441"}]}]}
    expected_output = {'@graph' => [{"performer" =>  [{"@id"=>"http://kg.artsdata.ca/resource/K10-440", "name" => "K10-440"},{"@id"=>"http://kg.artsdata.ca/resource/K10-441", "name" => "K10-441"}] }]}
    assert_equal expected_output, JsonldGenerator.delete_ids(jsonld)
  end


  ############################
  # test make_google_graph
  ############################

  test "remove datatypes" do
    input_graph = RDF::Graph.new << [:hello, @schema.startDate, RDF::Literal::DateTime.new("2020-07-14T08:00:00-04:00")]
    input_graph << [:hello, @schema.endDate, RDF::Literal::Date.new("2020-07-14")]
    expected_output = RDF::Graph.new << [:hello, @schema.startDate, RDF::Literal.new("2020-07-14T08:00:00-04:00")]
    expected_output << [:hello, @schema.endDate, RDF::Literal.new("2020-07-14")]
    assert_equal expected_output.dump(:ntriples), JsonldGenerator.make_google_graph(input_graph).dump(:ntriples)
  end

  test "handle list of startDates" do
    input_graph = RDF::Graph.new <<  [:hello, @schema.startDate, RDF::Literal::DateTime.new("2020-07-14T08:00:00-04:00")]
    input_graph << [:hello, @schema.startDate, RDF::Literal::DateTime.new("2020-07-15T08:00:00-04:00")]
    expected_output = RDF::Graph.new << [:hello, @schema.startDate, RDF::Literal.new("2020-07-14T08:00:00-04:00")]
    expected_output << [:hello, @schema.startDate, RDF::Literal.new("2020-07-15T08:00:00-04:00")]
    assert_equal JSON.parse(expected_output.dump(:jsonld)), JSON.parse(JsonldGenerator.make_google_graph(input_graph).dump(:jsonld))
  end

  ############################
  # test remove_annotations
  ############################
  
  test "remove_annotations" do
    g =  RDF::Graph.load("test/fixtures/files/event_2_dates_input.ttls", format: :ttl, rdfstar: true)
    expected_output = RDF::Graph.load("test/fixtures/files/event_2_dates_output_no_annotations.ttl", format: :ttl, rdfstar: true)
    actual = JsonldGenerator.remove_annotations(g)

    #pp JSON.parse(actual.dump(:jsonld, rdfstar: true))
    assert_equal JSON.parse(expected_output.dump(:jsonld)), JSON.parse(actual.dump(:jsonld))
  end


end
