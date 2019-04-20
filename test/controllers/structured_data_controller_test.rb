require 'test_helper'

class StructuredDataControllerTest < ActionDispatch::IntegrationTest
  test "should get event_markup" do
    get event_markup_structured_data_url(url: "http://festivaldesarts.ca/en/performances/feature-presentations/romeo-et-juliette/")
    assert_response :unprocessable_entity, {"error":"Mandatory Event fields need review: title, location, startDate for MyString"}
  end


  test "should get json-ld of webpage" do
    get webpage_structured_data_url(url: "http://festivaldesarts.ca/en/performances/feature-presentations/romeo-et-juliette/")
    assert_response :success
  end

end
