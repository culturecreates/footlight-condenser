require 'test_helper'

# StatementsHelper tests for search_cckg() only
class StatementsHelperSearchCckgTest < ActionView::TestCase
  tests StatementsHelper

  test "search_cckg: should search cckg for uris that match 100%" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: should search cckg for uris that match 100%') do
      expected = {:data=>[["Place des Arts - Théâtre Maisonneuve", "http://kg.artsdata.ca/resource/K11-11"]]}
      actual = search_cckg "Théâtre Maisonneuve", "Place"
      assert_equal expected, actual
    end
  end

  test "search_cckg: should search cckg for uris by matching name in substring" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: should search cckg for uris by matching name in substring') do
      expected = {:data=>[["St. Lawrence Centre for the Arts - Bluma Appel Theatre", "http://kg.artsdata.ca/resource/K11-6"], ["Canadian Stage - Berkeley Street Theatre", "http://kg.artsdata.ca/resource/K11-14"]]}
      actual = search_cckg "The locations is in the lovely Bluma Appel Theatre and Berkeley Street Theatre.", "Place"
      assert_equal expected, actual
    end
  end

  test "search_cckg: should search cckg for VaughnCo Entertainment presents" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: should search cckg for VaughnCo Entertainment presents') do
      expected = {data:[["VaughnCo Entertainment", "http://kg.artsdata.ca/resource/K10-148"]]}
      actual = search_cckg "VaughnCo Entertainment presents", "Organization"
      assert_equal expected, actual
    end
  end
  

  test "search_cckg: should search cckg for Wajdi Mouawad" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: should search cckg for Wajdi Mouawad') do
      expected = {data:[["Wajdi Mouawad", "http://kg.artsdata.ca/resource/K12-362"]]}
      actual = search_cckg "Wajdi Mouawad", "Person"
      assert_equal expected, actual
    end
  end
  

  test "search_cckg: should search cckg for nowhere" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: should search cckg for nowhere') do
      expected = {:data=>[]}
      actual = search_cckg "Show is at nowhere", "Place"
      assert_equal expected, actual
    end
  end

  test "search_cckg: remove duplicates" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: remove duplicates') do
      expected = {data:[["Canadian Stage - Berkeley Street Theatre", "http://kg.artsdata.ca/resource/K11-14"]]}
      actual = search_cckg "The locations is in the lovely Berkeley Street Theatre and Canadian Stage - Berkeley Street Theatre.", "Place"
      assert_equal expected, actual
    end
  end

  # NOT PASSING
  # TODO: Add searching with URL to Artsdata Reconciliation service.
  # test "search_cckg: using web url" do
  #   expected = {data:[["Rumours Tribute Show", "http://kg.artsdata.ca/resource/K10-180"]]}
  #   actual = search_cckg "https://www.rumourstributeshow.com/", "Organization"
  #   assert_equal expected, actual
  # end

  # # NOT PASSING
  # TODO: Add searching with URL to Artsdata Reconciliation service.
  # test "search_cckg: using web url of a PERSON" do
  #   expected = {data:[["Jason Cyrus", "http://kg.artsdata.ca/resource/K12-5"]]}
  #   actual = search_cckg "http://www.jasoncyrus.com", "Person"
  #   assert_equal expected, actual
  # end
  
  # Common words: example Person name that is removed "wiL", "http://kg.artsdata.ca/resource/K12-32"
  test "search_cckg: should not match names with common words" do  
    VCR.use_cassette('StatementsHelperSearchCckgTest: should not match names with common words') do
      expected = {data:[]}
      actual = search_cckg "The word will contains part of a first name.", "Person"
      assert_equal expected, actual
    end
  end

  test "search_cckg: should match names with single neutral quote" do  
    VCR.use_cassette('StatementsHelperSearchCckgTest: should match names with single neutral quote') do
      expected = {:data=>[["La P'tite Église (Shippagan)", "http://kg.artsdata.ca/resource/K11-131"]]}
      actual = search_cckg "Shippagan 20 h 00 La P'tite Église (Shippagan)", "Place"
      assert_equal expected, actual
    end
  end

  test "search_cckg: should match names with single curved quote" do  
    VCR.use_cassette('StatementsHelperSearchCckgTest: should match names with single curved quote') do
      expected = {:data=>[["Emily D’Angelo", "http://kg.artsdata.ca/resource/K12-150"]]}
      actual = search_cckg "Emily D’Angelo", "Person"
      assert_equal expected, actual
    end
  end
  

  test "search_cckg: should match names with &" do  
    VCR.use_cassette('StatementsHelperSearchCckgTest: should match names with &') do
      expected = {:data=>[["meagan&amy", "http://kg.artsdata.ca/resource/K10-376"]]}
      actual = search_cckg "meagan&amp;amy", "Organization"
      assert_equal expected, actual
    end
  end

  test "search_cckg: should match places with title in French" do  
    VCR.use_cassette('StatementsHelperSearchCckgTest: should match places with title in French') do
      expected = {:data=>[["Théâtre Marc Lescarbot", "http://kg.artsdata.ca/resource/K11-133"]]}
      actual = search_cckg "Théâtre Marc Lescarbot", "Place"
      assert_equal expected, actual
    end
  end

  test "search_cckg: find alternate names" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: find alternate names') do
      expected = {data:[["Dow Centennial Centre - Shell Theatre", "http://kg.artsdata.ca/resource/K11-64"]]}
      actual = search_cckg "Shell Theatre", "Place"
      assert_equal expected, actual
    end
  end


  test "search_cckg: find additional type using artsdata" do
    VCR.use_cassette('StatementsHelperSearchCckgTest: find additional types') do
      expected = {data:[["Dance", "http://kg.artsdata.ca/resource/DancePerformance"]]}
      actual = search_cckg("Dance", "EventType")
      assert_equal expected, actual
    end
  end


end
