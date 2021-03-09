require 'test_helper'

class JsonldGeneratorTest < ActiveSupport::TestCase
  # test method build_graph
  test "build_graph" do
    statements = [statements(:three)]
    nesting_options = {}
    expected_output = 2
    assert_equal expected_output, JsonldGenerator.build_graph(statements, nesting_options).count
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

  test "should remove all @ids inside @graph and in list of performers" do
    jsonld = {'@graph' => [{"performer" => [ {"@id" => "http://kg.artsdata.ca/resource/K10-440", "name" => "K10-440"},{"@id" => "http://kg.artsdata.ca/resource/K10-441", "name" => "K10-441"}]}]}
    expected_output = {'@graph' => [{"performer" =>  [{"name" => "K10-440"},{"name" => "K10-441"}] }]}
    assert_equal expected_output, JsonldGenerator.delete_ids(jsonld)
  end
end
