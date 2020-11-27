require 'test_helper'

class JsonldGeneratorTest < ActiveSupport::TestCase

  # test method build_graph
  test "build_graph" do
    rdf_uri = "adr:K11-11"
    statements = [statements(:three)]
    nesting_options =  { 1 => { 5 => 'http://schema.org/offers' } }
    expected_output = 2
    assert_equal expected_output, JsonldGenerator.build_graph(rdf_uri, statements, nesting_options, "Place").count
  end


  # test method extract_object_uris
  test "should extract no URIs" do
    graph = RDF::Graph.new << [:hello, RDF::RDFS.label, "Hello, world!"]
    expected_output = []
    assert_equal expected_output, JsonldGenerator.extract_object_uris(graph)
  end

  test "should extract one URIs" do
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

  # tests method make_google_jsonld
  test "should not fail with blank jsonld" do
    jsonld = ''
    assert_nil JsonldGenerator.make_google_jsonld(jsonld)
  end

  test "should remove graph node" do
    jsonld = {"@graph" => ["one" => "thing"]}
    expected_output = {"one" => "thing", "@context" => "https://schema.org/"}
    assert_equal expected_output, JsonldGenerator.make_google_jsonld(jsonld)
  end

  # tests method delete_ids
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
    expected_output = {"one" => "thing",  "organizer" =>  {"name" => "organizer name"}, "performer"=>{}, "location"=>{}}
    assert_equal expected_output, JsonldGenerator.delete_ids(jsonld)
  end
end
