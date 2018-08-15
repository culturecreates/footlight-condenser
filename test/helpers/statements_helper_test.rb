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

  test "should covert french date from webpage into ISO date" do
    expected_output = "2018-08-02"
    assert_equal expected_output, ISO_date("le jeudi 2 août 2018")
  end

  test "should covert english date from webpage into ISO date" do
    expected_output = "2018-08-02"
    assert_equal expected_output, ISO_date("Thursday, August 2, 2018")
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



end
