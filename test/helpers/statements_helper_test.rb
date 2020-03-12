require 'test_helper'

class StatementsHelperTest < ActionView::TestCase



#scrape
  test "should scrape title from html" do
    source = sources(:one)
    source.algorithm_value = "xpath=//title"
    expected_output = ['Culture Creates | Digital knowledge management for the arts']
    assert_equal expected_output, scrape(source, "http://culturecreates.com")
  end

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

  #status_checker (scraped_data, property)
  test "should have missing status" do
    property = properties(:nine)
    scraped_data = "a string without auto-links"
    expected_output = "missing"
    assert_equal expected_output, status_checker(scraped_data, property)
  end

  test "should have ok status" do
    property = properties(:nine)
    scraped_data = "[\"source\",\"class\",[\"name\",\"uri\"]]"
    expected_output = "initial"
    assert_equal expected_output, status_checker(scraped_data, property)
  end

  test "should have initial status for array of scraped data" do
    property = properties(:nine)
    scraped_data = "[[\"source\",\"class\",[\"name\",\"uri\"]],[\"source\",\"class\",[\"name\",\"uri\"]]]"
    expected_output = "initial"
    assert_equal expected_output, status_checker(scraped_data, property)
  end



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
   expected = ["Théâtre Maisonneuve", "Place", ["Théâtre Maisonneuve", "http://kg.artsdata.ca/resource/K11-11"]]
   assert_equal expected, actual
  end

  test "string input for any:URI scraped source" do
    property = properties(:nine)
    scraped_data = ["http://www.tnb.nb.ca/"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["http://www.tnb.nb.ca/", "Organization", ["Theatre New Brunswick", "http://kg.artsdata.ca/resource/K10-168"]]
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

   test "array string input for any:URI" do
    property = properties(:nine)
    scraped_data = ["CompanyKaha:wi Dance Theatre","ArtistsSantee Smith"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = [["CompanyKaha:wi Dance Theatre", "Organization", ["Kaha:wi Dance Theatre", "http://kg.artsdata.ca/resource/K10-206"]], ["ArtistsSantee Smith", "Organization"]]
    assert_equal expected, actual
   end

   test "format_datatype with time_zone" do
    property = properties(:ten)
    scraped_data = ["time_zone:  Eastern Time (US & Canada) ","2020-05-28T22:00:00-00:00", "2020-05-31T22:00:00-00:00"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["2020-05-28T18:00:00-04:00", "2020-05-31T18:00:00-04:00"]
    assert_equal expected, actual
   end

   test "format_datatype with NO time_zone" do
    property = properties(:ten)
    scraped_data = ["2020-05-28T22:00:00-01:00", "2020-05-31T22:00:00-01:00"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["2020-05-28T19:00:00-04:00", "2020-05-31T19:00:00-04:00"]
    assert_equal expected, actual
   end

   test "format_datatype with INVALID time_zone" do
    property = properties(:ten)
    scraped_data = ["time_zone:  Nowhere Time (US & Canada) ","2020-05-28T22:00:00-01:00", "2020-05-31T22:00:00-01:00"]
    webpage = webpages(:one)
    actual = format_datatype(scraped_data, property, webpage)
    expected = ["Bad input date_time: 2020-05-28T22:00:00-01:00 with error: #<ArgumentError: Invalid Timezone: Nowhere Time (US & Canada)>", "Bad input date_time: 2020-05-31T22:00:00-01:00 with error: #<ArgumentError: Invalid Timezone: Nowhere Time (US & Canada)>"]
    assert_equal expected, actual
   end


  #search_cckg
  test "search_cckg: should search cckg for uris that match 100%" do
    expected = {:data=>[["Théâtre Maisonneuve", "http://kg.artsdata.ca/resource/K11-11"]]}
    actual = search_cckg "Théâtre Maisonneuve", "Place"
    assert_equal expected, actual
  end

  test "search_cckg: should search cckg for uris by matching name in substring" do
    expected = {:data=>[["St. Lawrence Centre for the Arts - Bluma Appel Theatre", "http://kg.artsdata.ca/resource/K11-6"], ["Canadian Stage - Berkeley Street Theatre", "http://kg.artsdata.ca/resource/K11-14"]]}
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
    expected = {data:[["Canadian Stage - Berkeley Street Theatre", "http://kg.artsdata.ca/resource/K11-14"]]}
    actual = search_cckg "The locations is in the lovely Berkeley Street Theatre and Canadian Stage - Berkeley Street Theatre.", "Place"
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
  
  test "search_cckg: should not match names with common words" do  # Example Person name that is removed "wiL", "http://kg.artsdata.ca/resource/K12-32"
    expected = {data:[]}
    actual = search_cckg "The word will contains part of a first name.", "Person"
    assert_equal expected, actual
  end

  test "search_cckg: should match names with single neutral quote" do  
    expected = {:data=>[["La P'tite Église (Shippagan)", "http://kg.artsdata.ca/resource/K11-131"]]}
    actual = search_cckg "Shippagan 20 h 00 La P'tite Église (Shippagan)", "Place"
    assert_equal expected, actual
  end

  test "search_cckg: should match names with single curved quote" do  
    expected = {:data=>[["Emily D’Angelo", "http://kg.artsdata.ca/resource/K12-150"]]}
    actual = search_cckg "Emily D’Angelo", "Person"
    assert_equal expected, actual
  end
  

  test "search_cckg: should match names with &" do  
    expected = {:data=>[["meagan&amy", "http://kg.artsdata.ca/resource/K10-376"]]}
    actual = search_cckg "meagan&amp;amy", "Organization"
    assert_equal expected, actual
  end

  test "search_cckg: should match places with title in French" do  
    expected = {:data=>[["Théâtre Marc Lescarbot", "http://kg.artsdata.ca/resource/K11-133"]]}
    actual = search_cckg "Théâtre Marc Lescarbot", "Place"
    assert_equal expected, actual
  end

  test "search_cckg: find alternate names" do
    expected = {data:[["Dow Centennial Centre - Shell Theatre", "http://kg.artsdata.ca/resource/K11-64"]]}
    actual = search_cckg "Shell Theatre", "Place"
    assert_equal expected, actual
  end





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

  test "ISO_dateTime: should convert a date without time to Date instead of dateTime" do
    expected_output = "2020-05-31"
    assert_equal expected_output, ISO_dateTime("2020-05-31")
   end

  test "ISO_dateTime: should set timezone" do
    expected_output = "2020-05-31T18:00:00-04:00"
    assert_equal expected_output, ISO_dateTime("2020-05-31T22:00:00-00:00","Eastern Time (US & Canada)")
  end

  test "ISO_dateTime: should set timezone traversing day boundary" do
    expected_output = "2020-05-30T22:00:00-04:00"
    assert_equal expected_output, ISO_dateTime("2020-05-31T02:00:00-00:00","Eastern Time (US & Canada)")
  end


  test "ISO_dateTime: should convert text containing 'Halifax' to dateTime" do
    expected_output = "2020-03-06T19:00:00-05:00"
    assert_equal expected_output, ISO_dateTime("06 mar 2020   Halifax   19 h 00 ")
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

  test "process_linked_data_removal: delete when out of sync" do
    expected_output = [["https://www.atlanticballet.ca/en/home/","Organization", ["Ballet Atlantique Canada", "http://kg.artsdata.ca/resource/K10-16"]], ["Manually deleted", "Organization", ["Against the Grain Theatre", "http://kg.artsdata.ca/resource/K10-280"]]]
    statement_cache = [["https://www.atlanticballet.ca/en/home/","Organization", ["Ballet Atlantique Canada", "http://kg.artsdata.ca/resource/K10-16"]], ["Manually deleted", "Organization", ["Against the Grain Theatre", "http://kg.artsdata.ca/resource/K10-280"], ["Ballet Atlantique Canada", "http://kg.artsdata.ca/resource/K10-16"]]]

    assert_equal expected_output, process_linked_data_removal(statement_cache, "http://kg.artsdata.ca/resource/K10-16","Organization","Ballet Atlantique Canada")
  end
end
