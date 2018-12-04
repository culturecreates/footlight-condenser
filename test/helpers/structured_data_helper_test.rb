require 'test_helper'

class StructuredDataHelperTest < ActionView::TestCase



# build_events_per_startDate _jsonld
  test "build_events_per_startDate: only a date" do
    expected_output = [{"startDate"=>"Today"}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => ["Today"]})
  end

  test "build_events_per_startDate: 2 dates" do
    expected_output = [{"startDate"=>"Today"}, {"startDate"=>"Tomorrow"}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => ["Today", "Tomorrow"]})
  end

  test "build_events_per_startDate: 2 dates with one location" do
    expected_output = [{"startDate"=>"Today", "location"=>"one_place"}, {"startDate"=>"Tomorrow", "location"=>"one_place"}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => ["Today", "Tomorrow"], "location" => ["one_place"]})
  end

  test "build_events_per_startDate: 2 dates with 2 locations" do
    expected_output = [{"startDate"=>"Today", "location"=>"one_place"}, {"startDate"=>"Tomorrow", "location"=>"second_place"}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => ["Today", "Tomorrow"], "location" => ["one_place","second_place"]})
  end

  test "build_events_per_startDate: 2 dates with one duration" do
    expected_output = [{"startDate" => "Today", "duration" => "1 hr"}, {"startDate" => "Tomorrow", "duration" => "1 hr"}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => ["Today", "Tomorrow"], "duration" => ["1 hr"]})
  end

  test "build_events_per_startDate: 2 dates with 2 durations" do
    expected_output = [{"startDate"=>"Today", "duration"=>"1 hr"}, {"startDate"=>"Tomorrow", "duration"=>"2 hrs"}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => ["Today", "Tomorrow"], "duration" => ["1 hr","2 hrs"]})
  end



  test "build_events_per_startDate: 2 dates with 1 ticket offer url" do
    expected_output = [{"startDate"=>"Today", :offers =>{"url"=>"offer_url"}}, {"startDate"=>"Tomorrow", :offers =>{"url"=>"offer_url"}}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => ["Today", "Tomorrow"], :offers => {"url" => ["offer_url"]}})
  end

  test "build_events_per_startDate: 2 dates with 2 ticket offer urls" do
    expected_output = [{"startDate"=>"Today", :offers =>{"url"=>"offer_url_one"}}, {"startDate"=>"Tomorrow", :offers => {"url"=>"offer_url_two"}}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => ["Today", "Tomorrow"], :offers => {"url" => ["offer_url_one","offer_url_two"]}})
  end






# add_offer
  test "add_offer: simple cases with one url or price" do
    some_date = DateTime.new(2014, 12, 12, 1, 1, 1)
    Date.stubs(:today).returns(some_date)
    #add url
    expected_output = {:offers=>{:@type=>"Offer", "validFrom"=>"2014-12-12T01:01:01+00:00", "availability"=>"http://schema.org/InStock", "url"=>["http://ticket_link_url.com"]}}
    assert_equal expected_output, add_offer({},"url", "http://ticket_link_url.com")

    #add price
    expected_output = {:offers=>{:@type=>"Offer", "validFrom" => "2014-12-12T01:01:01+00:00", "availability"=>"http://schema.org/InStock", "price"=>"12.5", "priceCurrency"=>"CAD"}}
    assert_equal expected_output, add_offer({},"price", "12.5")

    #add url after adding price
    jsonld = add_offer({},"price", "12.5")
    expected_output = {:offers=>{:@type=>"Offer", "validFrom" => "2014-12-12T01:01:01+00:00", "availability" => "http://schema.org/InStock", "price" => "12.5", "priceCurrency" => "CAD", "url" => ["http://ticket_link_url.com"]}}
    assert_equal expected_output, add_offer(jsonld, "url", "http://ticket_link_url.com")
  end


  test "add_offer: multiple buy links" do
    some_date = DateTime.new(2014, 12, 12, 1, 1, 1)
    Date.stubs(:today).returns(some_date)
    expected_output = {:offers=>{:@type=>"Offer", "validFrom"=>"2014-12-12T01:01:01+00:00", "availability"=>"http://schema.org/InStock", "url"=>["http://ticket_link_one.com", "http://ticket_link_two.com"]}}
    assert_equal expected_output, add_offer({}, "url", "[\"http://ticket_link_one.com\", \"http://ticket_link_two.com\"]")
  end


  test "add_offer: Complet" do
    some_date = DateTime.new(2014, 12, 12, 1, 1, 1)
    Date.stubs(:today).returns(some_date)
    expected_output = {:offers=>{:@type=>"Offer", "validFrom"=>"2014-12-12T01:01:01+00:00", "availability"=>"http://schema.org/SoldOut"}}
    assert_equal expected_output, add_offer({}, "url", "[\"Complet\"]")
  end





# get_kg_place
  fass_place =   {"22-rdf-syntax-ns#type"=>"http://schema.org/PostalAddress", "addressCountry"=>"CA", "addressLocality"=>"Saint-Sauveur", "addressRegion"=>"QC", "postalCode"=>"J0R 1R0", "streetAddress"=>"167, rue Principale"}

  test "get_kg_place: should get fass place from cc knowledge graph" do
    expected_output = fass_place
    assert_equal expected_output, get_kg_place("http://artsdata.ca/resource/place/big_top_fass")
  end

  test "get_kg_place: should get non-existant place" do
    expected_output = {}
    assert_equal expected_output, get_kg_place("http://non-existant")
  end

  test "get_kg_place: should produce error with invalid URI" do
    expected_output = {:error=>"Bad Request"}
    assert_equal expected_output, get_kg_place("invalid-uri")
  end

  test "get_kg_place: should get fass place using PREFIX" do
    expected_output = fass_place
    assert_equal expected_output, get_kg_place("adr:place/big_top_fass")
  end

#tests for make_into_array()
  test "make_into_array: string" do
    expected_output = ["hello"]
    assert_equal expected_output, make_into_array("hello")
  end

  test "make_into_array: string of array" do
    expected_output = ["hello","there"]
    assert_equal expected_output, make_into_array("[\"hello\",\"there\"]")
  end

end
