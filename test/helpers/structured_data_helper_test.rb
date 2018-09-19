require 'test_helper'

class StructuredDataHelperTest < ActionView::TestCase

  fass_place =   {"22-rdf-syntax-ns#type"=>"http://schema.org/PostalAddress", "addressCountry"=>"Canada", "addressLocality"=>"Saint-Sauveur", "addressRegion"=>"Québec", "postalCode"=>"J0R 1R0", "streetAddress"=>"167, rue Principale"}

  test "should get fass place from cc knowledge graph" do
    expected_output = fass_place
    assert_equal expected_output, get_kg_place("http://corpo.culturecreates.com/#place_big_top_saint_sauveur")
  end

  test "should get non-existant place" do
    expected_output = {}
    assert_equal expected_output, get_kg_place("http://non-existant")
  end

  test "should produce error with invalid URI" do
    expected_output = {:error=>"#<Net::HTTPBadRequest 400 Bad Request readbody=true>"}
    assert_equal expected_output, get_kg_place("invalid-uri")
  end

  test "should get fass place using PREFIX" do
    expected_output = fass_place
    assert_equal expected_output, get_kg_place("adr:place_big_top_saint_sauveur")
  end
end
