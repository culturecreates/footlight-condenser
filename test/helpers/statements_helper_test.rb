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

  test "should convert to ISO date time" do
   expected_output = "2019-07-03T20:30:00-04:00"
   assert_equal expected_output, ISO_dateTime("3 juillet 2019 - 20 h 30")
  end

  test "should convert août to ISO date time" do
   expected_output = "2019-08-09T20:30:00-04:00"
   assert_equal expected_output, ISO_dateTime("9 août 2019 - 20 h 30")
  end


end
