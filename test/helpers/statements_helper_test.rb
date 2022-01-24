require 'test_helper'

# Part of StatmentsHelper. See other test files for search_cckg and format_datatype tests. 
class StatementsHelperTest < ActionView::TestCase


#process algorithm
test "process_algorithm manual" do
  expected = ["Test"]
  assert_equal expected, process_algorithm(algorithm: "manual=Test", url: "http://culturecreates.com")
end
test "process_algorithm xpath" do
  expected = ["Culture Creates | Digital knowledge management for the arts"]
  VCR.use_cassette('StatementsHelper:culturecreates.com') do
    assert_equal expected, process_algorithm(algorithm: "xpath=//title", url: "http://culturecreates.com")
  end
end
test "process_algorithm url and xpath" do
  expected = ["ArtsdataApi"]
  VCR.use_cassette('StatementsHelper:process_algorithm url and xpath') do
    assert_equal expected, process_algorithm(algorithm: "url='http://api.artsdata'+'.ca';xpath=//title", url: "http://culturecreates.com")
  end
end
test "process_algorithm double xpath" do
  expected = ["Culture Creates | Digital knowledge management for the arts", "IE=edge"]
  VCR.use_cassette('StatementsHelper:culturecreates.com') do
    assert_equal expected, process_algorithm(algorithm: "xpath=//title;xpath=(//meta/@content)[1]", url: "http://culturecreates.com")
  end
end
test "process_algorithm url and json and ruby" do
  expected = ["2021-04-10 10:00:00", "time_zone: 'Eastern Time (US & Canada)'"]
  algo = "url=$url + '.json';json=$json.dig('date','end');ruby=$array[0] ? [$json.dig('date','start')] : $array;time_zone='Eastern Time (US & Canada)'"
  VCR.use_cassette('StatementsHelper: process_algorithm url and json and ruby') do
    assert_equal expected, process_algorithm(algorithm: algo,  url: "https://signelaval.com/fr/evenements/14650/du-fond-de-mon-garde-robe")
  end
end
test "process_algorithm ruby syntax error" do
  expected = ["abort_update", {:error=>"(eval):1: syntax error, unexpected end-of-input, expecting '}' results_list.each {|a| a ^", :error_type=>SyntaxError, :results_prior=>[], :algorithm_rescued=>"ruby=$array.each {|a| a"}]
  algo = "ruby=$array.each {|a| a"
  assert_equal expected, process_algorithm(algorithm: algo,  url: "https://signelaval.com/fr/evenements/14650/du-fond-de-mon-garde-robe")
end
test "process_algorithm invalid algorithm prefix" do
  expected = [["abort_update", {:error=>"Missing valid prefix", :algorithm=>"//title"}]]
  algo = "//title"
  assert_equal expected, process_algorithm(algorithm: algo,  url: "https://signelaval.com/fr/evenements/14650/du-fond-de-mon-garde-robe")
end


#scrape
  test "should scrape title from html" do
    source = sources(:one)
    source.algorithm_value = "xpath=//title"
    expected_output = ['Culture Creates | Digital knowledge management for the arts']
    VCR.use_cassette('StatementsHelper: should scrape title from html') do
      assert_equal expected_output, scrape(source, "http://culturecreates.com")
    end
  end

  test "should scrape 2 items from html" do
    source = OpenStruct.new(algorithm_value: 'xpath=//title;xpath=//meta[@property="og:title"]/@content')
    expected_output = ['Culture Creates | Digital knowledge management for the arts', "Culture Creates Inc"]
    VCR.use_cassette('StatementsHelper: should scrape 2 items from html') do
      assert_equal expected_output, scrape(source, "http://culturecreates.com")
    end
  end


  test "should concatenate 2 items from html" do
    source = OpenStruct.new(algorithm_value: 'xpath=//title;xpath=//meta[@property="og:title"]/@content;ruby=$array[0]+ " | " + $array[1]')
    expected_output = "Culture Creates | Digital knowledge management for the arts | Culture Creates Inc"
    VCR.use_cassette('StatementsHelper: should concatenate 2 items from html') do
      assert_equal expected_output, scrape(source, "http://culturecreates.com")
    end
  end

  # search_condenser
  test "search_condenser: should search condenser for uris that match 100%" do
    expected = {:data=>[["Statement Six Name", "adr:seven"]]}
    actual = search_condenser("Statement Six Name", "Place")
    assert_equal expected, actual
  end

  test "search_condenser: should search condenser for uris by matching name in substring" do
    expected = {:data=>[["Statement Six Name", "adr:seven"]]}
    actual = search_condenser("Show is at Statement Six Name", "Place")
    assert_equal expected, actual
  end

  test "search_condenser: should search condenser for nowhere" do
    expected = {data:[]}
    actual = search_condenser("Show is at nowhere", "Place")
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
    expected_output = ""
    assert_equal expected_output, ISO_duration("There is nothing here")
  end

  # TODO: improve NLP of duration extraction
  # test "ISO_duration: should convert messy string to ISO duration" do
  #   expected_output = "PT3600S"
  #   assert_equal expected_output, ISO_duration(" samedi 20 octobre 2018, de 10 h à 11 h ")
  # end


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
