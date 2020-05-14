require 'test_helper'

class JsonldGeneratorTest < ActiveSupport::TestCase
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

  test "should extract one uri" do
    cache = '["source text", "Expected Class", [ "Entity label", "http://example.com" ]]'
    expected_output = ["http://example.com"]
    assert_equal expected_output, JsonldGenerator.extract_uris_from_cache(cache)
  end

  test "should extract two uris" do
    cache = '["source text", "Expected Class", [ "Entity 1", "http://example.com#1" ], [ "Entity 2", "http://example.com#2" ] ]'
    expected_output = ["http://example.com#1", "http://example.com#2"]
    assert_equal expected_output, JsonldGenerator.extract_uris_from_cache(cache)
  end

  test "should extract uri 3 and not the deleted uri 1" do
    cache = '[["text", "Class", [ "Entity 1", "http://example.com#1" ]],["text 3", "Class 3", [ "Entity 3", "http://example.com#3" ] ],["Manually deleted", "Class",["Label","http://example.com#1"]]]'
    expected_output = ["http://example.com#3"]
    assert_equal expected_output, JsonldGenerator.extract_uris_from_cache(cache)
  end

  test "should extract  uri 2 from double link and not the deleted uri 1" do
    cache = '[["source text", "Expected Class", [ "Entity 1", "http://example.com#1" ], [ "Entity 2", "http://example.com#2" ] ],["Manually deleted", "Class",["Label","http://example.com#1"]]]'
    expected_output = ["http://example.com#2"]
    assert_equal expected_output, JsonldGenerator.extract_uris_from_cache(cache)
  end

end