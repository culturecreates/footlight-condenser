require 'test_helper'

class GraphsControllerTest < ActionDispatch::IntegrationTest
  # test "the truth" do
  #   assert true
  # end

  setup do
    @controller = GraphsController.new
  end

  test "should extract no URIs" do
    graph = RDF::Graph.new << [:hello, RDF::RDFS.label, "Hello, world!"]
    expected_output = []
    assert_equal expected_output, @controller.instance_eval{extract_object_uris(graph)}
  end


  test "should extract one URIs" do
    graph = RDF::Graph.new << [:hello, RDF::RDFS.label, RDF::URI.new("http://one.com")]
    graph << [:hello, RDF::RDFS.label, RDF::URI.new("http://two.com")]
    expected_output = [RDF::URI.new("http://two.com"),RDF::URI.new("http://one.com")].sort
    assert_equal expected_output, @controller.instance_eval{extract_object_uris(graph)}.sort
  end


  test "should return graph" do
   
    uri = RDF::URI.new("http://kg.artsdata.ca/resource/K10-344")
    expected_output = 18
    assert_equal expected_output, @controller.instance_eval{describe_uri(uri)}.count
  end

  test "should return graph for K12-170" do
    uri = RDF::URI.new("http://kg.artsdata.ca/resource/K12-170")
    expected_output = 9
    assert_equal expected_output, @controller.instance_eval{describe_uri(uri)}.count
  end

end
