require 'test_helper'

class StructuredDataHelperTest < ActionView::TestCase

  TESTDATETIME_TODAY = "2019-01-01T20:00:00-04:00"
  TESTDATETIME_TOMORROW = "2019-01-02T20:00:00-04:00"

  TESTDATE_TODAY = "2019-01-01"
  TESTDATE_TOMORROW = "2019-01-02"


# build_jsonld_for_class main_rdfs_class, condensor_statements

  setup do
    @main_rdfs_class = rdfs_classes(:one)
  end

  test "build_jsonld_for_class: simple list" do
    expected_output = [{"@type"=>"Event", "name"=>"StatementOne", "description"=>"StatementTwo"}]
    assert_equal expected_output, build_jsonld_for_class(@main_rdfs_class.name, [statements(:one),statements(:two)])
  end

  test "build_jsonld_for_class: mulitple item list" do
    expected_output = [{"@type"=>"Event", "dates"=>"date1", "location"=>"montreal"}, {"@type"=>"Event", "dates"=>"date2", "location"=>"toronto"}]
    assert_equal expected_output, build_jsonld_for_class(@main_rdfs_class.name, [statements(:four),statements(:five)])
  end



# build_events_per_startDate _jsonld
  test "build_events_per_startDate: only a date" do
    expected_output = [{"startDate"=>TESTDATETIME_TODAY, "endDate"=>TESTDATE_TODAY}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => [TESTDATETIME_TODAY]})
  end

  test "build_events_per_startDate: 2 dates" do
    expected_output = [{"startDate"=>TESTDATETIME_TODAY, "endDate"=>TESTDATE_TODAY}, {"startDate"=>TESTDATETIME_TOMORROW, "endDate"=>TESTDATE_TOMORROW}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => [TESTDATETIME_TODAY, TESTDATETIME_TOMORROW]})
  end

  test "build_events_per_startDate: 2 dates with one location" do
    expected_output = [{"startDate"=>TESTDATETIME_TODAY, "endDate"=>TESTDATE_TODAY, "location"=>"one_place"}, {"startDate"=>TESTDATETIME_TOMORROW, "endDate"=>TESTDATE_TOMORROW, "location"=>"one_place"}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => [TESTDATETIME_TODAY, TESTDATETIME_TOMORROW], "location" => ["one_place"]})
  end

  test "build_events_per_startDate: 2 dates with 2 locations" do
    expected_output = [{"startDate"=>TESTDATETIME_TODAY, "endDate"=>TESTDATE_TODAY, "location"=>"one_place"}, {"startDate"=>TESTDATETIME_TOMORROW, "endDate"=>TESTDATE_TOMORROW, "location"=>"second_place"}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => [TESTDATETIME_TODAY, TESTDATETIME_TOMORROW], "location" => ["one_place","second_place"]})
  end

  test "build_events_per_startDate: 2 dates with one duration" do
    expected_output = [{"startDate" => TESTDATETIME_TODAY, "endDate"=>TESTDATE_TODAY, "duration" => "1 hr"}, {"startDate" => TESTDATETIME_TOMORROW, "endDate"=>TESTDATE_TOMORROW, "duration" => "1 hr"}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => [TESTDATETIME_TODAY, TESTDATETIME_TOMORROW], "duration" => ["1 hr"]})
  end

  test "build_events_per_startDate: 2 dates with 2 durations" do
    expected_output = [{"startDate"=>TESTDATETIME_TODAY, "endDate"=>TESTDATE_TODAY, "duration"=>"1 hr"}, {"startDate"=>TESTDATETIME_TOMORROW, "endDate"=>TESTDATE_TOMORROW, "duration"=>"2 hrs"}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => [TESTDATETIME_TODAY, TESTDATETIME_TOMORROW], "duration" => ["1 hr","2 hrs"]})
  end



  test "build_events_per_startDate: 2 dates with 1 ticket offer url" do
    expected_output = [{"startDate"=>TESTDATETIME_TODAY, "endDate"=>TESTDATE_TODAY, :offers =>{"url"=>"offer_url"}}, {"startDate"=>TESTDATETIME_TOMORROW, "endDate"=>TESTDATE_TOMORROW, :offers =>{"url"=>"offer_url"}}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => [TESTDATETIME_TODAY, TESTDATETIME_TOMORROW], :offers => {"url" => ["offer_url"]}})
  end

  test "build_events_per_startDate: 2 dates with 2 ticket offer urls" do
    expected_output = [{"startDate"=>TESTDATETIME_TODAY, "endDate"=>TESTDATE_TODAY, :offers =>{"url"=>"offer_url_one"}}, {"startDate"=>TESTDATETIME_TOMORROW, "endDate"=>TESTDATE_TOMORROW, :offers => {"url"=>"offer_url_two"}}]
    assert_equal expected_output, build_events_per_startDate({"startDate" => [TESTDATETIME_TODAY, TESTDATETIME_TOMORROW], :offers => {"url" => ["offer_url_one","offer_url_two"]}})
  end






# add_offer
  test "add_offer: simple cases with one url or price" do
    some_date = DateTime.new(2014, 12, 12, 1, 1, 1)
    Date.stubs(:today).returns(some_date)
    #add url
    expected_output = {:offers=>{:@type=>"Offer", "validFrom"=>"2014-11-12T01:01:01+00:00", "availability"=>"http://schema.org/InStock", "url"=>["http://ticket_link_url.com"]}}
    assert_equal expected_output, add_offer({},"url", "http://ticket_link_url.com")

    #add price
    expected_output = {:offers=>{:@type=>"Offer", "validFrom" => "2014-11-12T01:01:01+00:00", "availability"=>"http://schema.org/InStock", "price"=>"12.5", "priceCurrency"=>"CAD"}}
    assert_equal expected_output, add_offer({},"price", "12.5")

    #add url after adding price
    jsonld = add_offer({},"price", "12.5")
    expected_output = {:offers=>{:@type=>"Offer", "validFrom" => "2014-11-12T01:01:01+00:00", "availability" => "http://schema.org/InStock", "price" => "12.5", "priceCurrency" => "CAD", "url" => ["http://ticket_link_url.com"]}}
    assert_equal expected_output, add_offer(jsonld, "url", "http://ticket_link_url.com")
  end


  test "add_offer: multiple buy links" do
    some_date = DateTime.new(2014, 12, 12, 1, 1, 1)
    Date.stubs(:today).returns(some_date)
    expected_output = {:offers=>{:@type=>"Offer", "validFrom"=>"2014-11-12T01:01:01+00:00", "availability"=>"http://schema.org/InStock", "url"=>["http://ticket_link_one.com", "http://ticket_link_two.com"]}}
    assert_equal expected_output, add_offer({}, "url", "[\"http://ticket_link_one.com\", \"http://ticket_link_two.com\"]")
  end


  test "add_offer: Complet" do
    some_date = DateTime.new(2014, 12, 12, 1, 1, 1)
    Date.stubs(:today).returns(some_date)
    expected_output = {:offers=>{:@type=>"Offer", "validFrom"=>"2014-11-12T01:01:01+00:00", "availability"=>"http://schema.org/SoldOut"}}
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


#tests for publishable
  test "publishable? no date" do
    assert_equal  true, publishable?(JSON.parse("{\"startDate\" : [\"startDate\"], \"location\" : [\"location\"], \"name\" : \"name\"}"))
  end



end
