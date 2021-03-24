require 'test_helper'

class CcWringerHelperTest < ActionView::TestCase


  test "should get wringer url for DEV" do
    expected_output = "http://localhost:3009"
    assert_equal expected_output, get_wringer_url_per_environment()
  end


  test "should convert url for wringer" do
    expected_output = "http://localhost:3009/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true"
    assert_equal expected_output, use_wringer("http://culturecreates.com", false)
  end

  test "should convert url for wringer using phantomjs" do
    expected_output = "http://localhost:3009/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true&use_phantomjs=true"
    assert_equal expected_output, use_wringer("http://culturecreates.com", true)
  end

  test "should convert url for wringer using json_post" do
    expected_output = "http://localhost:3009/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true&json_post=true"
    assert_equal expected_output, use_wringer("http://culturecreates.com", false, { json_post: true })
  end


  # test "should call wringer to condense and add webpage to knowledge graph" do
  #   expected_output = ""
  #   url = "https://www.dansedanse.ca/en/dada-masilo-dance-factory-johannesburg-giselle"
  #   graph_uri = "http://artsdata.ca"
  #   jsonld = {}
  #   assert_equal expected_output, update_jsonld_on_wringer(url, graph_uri, jsonld)
  # end
  #
  #
  # test "should call wringer to delete condensed file" do
  #   expected_output = ""
  #   url = "https://www.dansedanse.ca/en/dada-masilo-dance-factory-johannesburg-giselle"
  #   graph_uri = "http://artsdata.ca"
  #   jsonld = {}
  #   assert_equal expected_output, update_jsonld_on_wringer(url, graph_uri, jsonld)
  # end
end
