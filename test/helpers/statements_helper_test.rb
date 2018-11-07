require 'test_helper'

class StatementsHelperTest < ActionView::TestCase

  # test "should scrape title from html" do
  #   source = sources(:one)
  #   source.algorithm_value = "xpath=//title"
  #   expected_output = ['Culture Creates | Digital knowledge management for the arts']
  #   assert_equal expected_output, scrape(source, "http://culturecreates.com")
  # end

  test "should covert url for wringer" do
    expected_output = "http://footlight-wringer.herokuapp.com/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true"
    assert_equal expected_output, use_wringer("http://culturecreates.com", false)
  end

  test "should covert url for wringer using phantomjs" do

    expected_output = "http://footlight-wringer.herokuapp.com/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true&use_phantomjs=true"
    assert_equal expected_output, use_wringer("http://culturecreates.com", true)
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

  # search_condenser
  test "search_condenser: should search condenser for uris that match 100%" do
    expected = [["myPlaceName", "httpUri"]]
    actual = search_condenser "myPlaceName", "Place"
    assert_equal expected, actual
  end

  test "search_condenser: should search condenser for uris by matching name in substring" do
    expected = [["myPlaceName", "httpUri"]]
    actual = search_condenser "Show is at myPlaceName", "Place"
    assert_equal expected, actual
  end

  test "search_condenser: should search condenser for nowhere" do
    expected = []
    actual = search_condenser "Show is at nowhere", "Place"
    assert_equal expected, actual
  end



  #search_cckg
  test "search_cckg: should search cckg for uris that match 100%" do
    expected = [["Southam Hall", "http://corpo.culturecreates.com/#place_southam_hall"]]
    actual = search_cckg "Southam Hall", "Place"
    assert_equal expected, actual
  end

  test "search_cckg: should search cckg for uris by matching name in substring" do
    expected =[["Berkeley Street Theatre", "http://corpo.culturecreates.com/#place_berkeley_street_theatre"], ["Southam Hall", "http://corpo.culturecreates.com/#place_southam_hall"]]
    actual = search_cckg "The locations is in the lovely Southam Hall and Berkeley Street Theatre.", "Place"
    assert_equal expected, actual
  end

  test "search_cckg: should search condenser for nowhere" do
    expected = []
    actual = search_cckg "Show is at nowhere", "Place"
    assert_equal expected, actual
  end

  test "search_cckg: remove duplicates" do
    expected = [["Southam Hall", "http://corpo.culturecreates.com/#place_southam_hall"]]
    actual = search_cckg "The locations is in the lovely Southam Hall and Southam Hall.", "Place"
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
  #
  # test "ISO_duration: should convert messy string to ISO duration" do
  #   expected_output = "PT3600S"
  #   assert_equal expected_output, ISO_duration(" samedi 20 octobre 2018, de 10 h à 11 h ")
  # end

 # href="/Pages/Fr/Calendrier/semaine-lavalloise-aines-activites-organismes.aspx"
  #du 10 octobre 2018, 4 h, au 22 octobre 2018, 3 h 59

#  href="/Pages/Fr/Calendrier/consultation-politique-stationnement.aspx">
  #du 22 octobre 2018, 23 h, au 23 octobre 2018, 2 h



end
