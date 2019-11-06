require 'test_helper'

class StatementsHelperTest < ActionView::TestCase

  # test "should scrape title from html" do
  #   source = sources(:one)
  #   source.algorithm_value = "xpath=//title"
  #   expected_output = ['Culture Creates | Digital knowledge management for the arts']
  #   assert_equal expected_output, scrape(source, "http://culturecreates.com")
  # end


  # test "should scrape 2 items from html" do
  #   source = OpenStruct.new(algorithm_value: 'xpath=//title,xpath=//meta[@property="og:title"]/@content')
  #   expected_output = ['Culture Creates | Digital knowledge management for the arts', "Culture Creates Inc"]
  #   assert_equal expected_output, scrape(source, "http://culturecreates.com")
  # end


  # test "should concatenate 2 items from html" do
  #   source = OpenStruct.new(algorithm_value: 'xpath=//title,xpath=//meta[@property="og:title"]/@content,ruby=$array[0]+ " | " + $array[1]')
  #   expected_output = "Culture Creates | Digital knowledge management for the artsCulture | Creates Inc"
  #   assert_equal expected_output, scrape(source, "http://culturecreates.com")
  # end

  # search_condenser
  test "search_condenser: should search condenser for uris that match 100%" do
    expected = {data:[["myPlaceName", "httpUri"]]}
    actual = search_condenser "myPlaceName", "Place"
    assert_equal expected, actual
  end

  test "search_condenser: should search condenser for uris by matching name in substring" do
    expected = {data:[["myPlaceName", "httpUri"]]}
    actual = search_condenser "Show is at myPlaceName", "Place"
    assert_equal expected, actual
  end

  test "search_condenser: should search condenser for nowhere" do
    expected = {data:[]}
    actual = search_condenser "Show is at nowhere", "Place"
    assert_equal expected, actual
  end


#format_datatype (scraped_data, property, webpage)
  test "prexisting array input for any:URI manual source" do
   property = properties(:seven)
   scraped_data = ["[\"name\",\"Class\",[\"remote name\",\"uri\"]]"]
   webpage = webpages(:one)
   actual = format_datatype(scraped_data, property, webpage)
   expected = ["name", "Class", ["remote name", "uri"]]
   assert_equal expected, actual
  end

  test "string input for any:URI manual source" do
   property = properties(:seven)
   scraped_data = ["Théâtre Maisonneuve"]
   webpage = webpages(:one)
   actual = format_datatype(scraped_data, property, webpage)
   expected = ["Théâtre Maisonneuve", "Place", ["Théâtre Maisonneuve", "http://kg.artsdata.ca/resource/place/theatre_maisonneuve"]]
   assert_equal expected, actual
  end

  test "string input for any:URI scraped source" do
    property = properties(:nine)
    scraped_data = ["http://www.tnb.nb.ca/"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["http://www.tnb.nb.ca/", "Organization", ["Theatre New Brunswick", "http://kg.artsdata.ca/resource/K10-154"]]
    assert_equal expected, actual
   end

  test "string input for any:URI scraped LONG url source" do
    property = properties(:nine)
    scraped_data = ["http://www.taramacleanmusic.com/home"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["http://www.taramacleanmusic.com/home", "Organization", ["Tara MacLean", "http://kg.artsdata.ca/resource/K12-14"]]
    assert_equal expected, actual
   end

  test "EMPTY string input for any:URI" do
    property = properties(:nine)
    scraped_data = []
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = []
    assert_equal expected, actual
   end




  #search_cckg
  test "search_cckg: should search cckg for uris that match 100%" do
    expected = {:data=>[["Théâtre Maisonneuve", "http://kg.artsdata.ca/resource/place/theatre_maisonneuve"]]}
    actual = search_cckg "Théâtre Maisonneuve", "Place"
    assert_equal expected, actual
  end

  test "search_cckg: should search cckg for uris by matching name in substring" do
    expected = {data:[["Bluma Appel Theatre", "http://kg.artsdata.ca/resource/place/bluma_appel_theatre"], ["Berkeley Street Theatre", "http://kg.artsdata.ca/resource/K11-14"]]}
    actual = search_cckg "The locations is in the lovely Bluma Appel Theatre and Berkeley Street Theatre.", "Place"
    assert_equal expected, actual
  end

  test "search_cckg: should search cckg for VaughnCo Entertainment presents" do
    expected = {data:[["VaughnCo Entertainment", "http://kg.artsdata.ca/resource/K10-148"]]}
    actual = search_cckg "VaughnCo Entertainment presents", "Organization"
    assert_equal expected, actual
  end
  

  test "search_cckg: should search cckg for nowhere" do
    expected = {:data=>[]}
    actual = search_cckg "Show is at nowhere", "Place"
    assert_equal expected, actual
  end

  test "search_cckg: remove duplicates" do
    expected = {data:[["Berkeley Street Theatre", "http://kg.artsdata.ca/resource/K11-14"]]}
    actual = search_cckg "The locations is in the lovely Berkeley Street Theatre and Berkeley Street.", "Place"
    assert_equal expected, actual
  end

  test "search_cckg: using web url" do
    expected = {data:[["Rumours Tribute Show", "http://kg.artsdata.ca/resource/K10-180"]]}
    actual = search_cckg "https://www.rumourstributeshow.com/", "Organization"
    assert_equal expected, actual
  end

  test "search_cckg: using web url of a PERSON" do
    expected = {data:[["Jason Cyrus", "http://kg.artsdata.ca/resource/K12-5"]]}
    actual = search_cckg "http://www.jasoncyrus.com", "Person"
    assert_equal expected, actual
  end
  




  # test "search_cckg: find alternate names" do
  #   expected = {data:[["Red Sky Performance", "http://artsdata.ca/resource/org/red_sky_performance"]]}
  #   actual = search_cckg "The dance group also known as Red-Sky-Performance is also known as Red Sky.", "Organization"
  #   assert_equal expected, actual
  # end





  # french_to_english_month
  test "french_to_english_month: should covert french month mai to english" do
    expected_output = "7 MAY 2019 - 20 h"
    assert_equal expected_output, french_to_english_month("7 mai 2019 - 20 h")
  end

  test "french_to_english_month: should covert accented french month fév to english" do
    expected_output = "7 FEB 2019 - 20 h"
    assert_equal expected_output, french_to_english_month("7 fév 2019 - 20 h")
  end

  test "french_to_english_month: should covert capitalized french month fév to english" do
    expected_output = "7 FEB 2019 - 20 h"
    assert_equal expected_output, french_to_english_month("7 Fév 2019 - 20 h")
  end

  test "french_to_english_month: should covert french month février to FEB with spacer" do
    expected_output = "7 FEB 2019 - 20 h"
    assert_equal expected_output, french_to_english_month("7 Février 2019 - 20 h")
  end

  # ISO_dateTime
  test "ISO_dateTime: should convert to ISO date time" do
   expected_output = "2019-07-03T20:30:00-04:00"
   assert_equal expected_output, ISO_dateTime("3 juillet 2019 - 20 h 30")
  end

  test "ISO_dateTime: should convert août to ISO date time" do
   expected_output = "2019-08-09T20:30:00-04:00"
   assert_equal expected_output, ISO_dateTime("9 août 2019 - 20 h 30")
  end

  test "ISO_dateTime: should convert date and time range to ISO date start time" do
   expected_output = "2018-10-20T10:00:00-04:00"
   assert_equal expected_output, ISO_dateTime(" samedi 20 octobre 2018, de 10 h à 11 h ")
  end



  #ISO_duration(duration_str)
  test "ISO_duration: should convert to ISO duration" do
   expected_output = "PT8400S"
   assert_equal expected_output, ISO_duration("2 hrs 20 min")
  end

  test "ISO_duration: should convert 2 h to ISO duration" do
    expected_output = "PT7200S"
    assert_equal expected_output, ISO_duration("duration 2 h")
  end

  test "ISO_duration: should convert 2 h 30 to ISO duration" do
    expected_output = "PT9000S"
    assert_equal expected_output, ISO_duration("duration: 2 h 30 m")
  end

  test "ISO_duration: should find no duration" do
    expected_output = "No duration found: There is nothing here"
    assert_equal expected_output, ISO_duration("There is nothing here")
  end



  #
  # test "ISO_duration: should convert messy string to ISO duration" do
  #   expected_output = "PT3600S"
  #   assert_equal expected_output, ISO_duration(" samedi 20 octobre 2018, de 10 h à 11 h ")
  # end

 # href="/Pages/Fr/Calendrier/semaine-lavalloise-aines-activites-organismes.aspx"
  #du 10 octobre 2018, 4 h, au 22 octobre 2018, 3 h 59

#  href="/Pages/Fr/Calendrier/consultation-politique-stationnement.aspx">
  #du 22 octobre 2018, 23 h, au 23 octobre 2018, 2 h



  #process_linked_data_removal statement_cache, uri_to_delete, class_to_delete, label_to_delete
  test "process_linked_data_removal: delete a link added manually" do
    expected_output = []
    statement_cache = ["Manually added","Place",["Theatre1","http://uri.com"]]
    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://uri.com","Place","Theatre1")
  end

  test "process_linked_data_removal: delete a link added automatically" do
    expected_output = [["Auto","Place",["Theatre1","http://uri.com"]],["Manually deleted", "Place", ["Theatre1", "http://uri.com"]]]
    statement_cache = ["Auto","Place",["Theatre1","http://uri.com"]]
    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://uri.com","Place","Theatre1")
  end

  test "process_linked_data_removal: delete a second link added automatically" do
    expected_output =[["Auto", "Place", ["Theatre9", "http://uri9.com"], ["Theatre1", "http://uri.com"]], ["Manually deleted", "Place", ["Theatre1", "http://uri.com"]]]
    statement_cache = ["Auto","Place",["Theatre9","http://uri9.com"],["Theatre1","http://uri.com"]]
    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://uri.com","Place","Theatre1")
  end


  test "process_linked_data_removal: delete a deleted link" do
    expected_output = [["Auto", "Place", ["Theatre9", "http://uri9.com"]]]
    statement_cache = [["Auto", "Place", ["Theatre9", "http://uri9.com"]], ["Manually deleted", "Place", ["Theatre1", "http://uri.com"]]]
    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://uri.com","Place","Theatre1")
  end


  test "process_linked_data_removal: delete a second manually added link" do
    expected_output = [["Auto", "Place", ["Theatre9", "http://uri9.com"]],["Manually deleted", "Place", ["Theatre1", "http://uri.com"]]]
    statement_cache = [["Auto", "Place", ["Theatre9", "http://uri9.com"]],["Manually added", "Place", ["Theatre2", "http://uri2.com"]],["Manually deleted", "Place", ["Theatre1", "http://uri.com"]]]
    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://uri2.com","Place","Theatre2")
  end

  test "process_linked_data_removal: delete a second auto added link" do
    expected_output = [["Auto", "Place", ["Theatre9", "http://uri9.com"]],["Manually added", "Place", ["Theatre2", "http://uri2.com"]],["Manually deleted", "Place", ["Theatre1", "http://uri.com"],["Theatre9", "http://uri9.com"]]]
    statement_cache = [["Auto", "Place", ["Theatre9", "http://uri9.com"]],["Manually added", "Place", ["Theatre2", "http://uri2.com"]],["Manually deleted", "Place", ["Theatre1", "http://uri.com"]]]
    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://uri9.com","Place","Theatre9")
  end





end
