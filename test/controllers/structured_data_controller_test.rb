require 'test_helper'

class StructuredDataControllerTest < ActionDispatch::IntegrationTest
  test "should get event_markup" do
    get structured_data_event_markup_url(url: "http://festivaldesarts.ca/en/performances/feature-presentations/romeo-et-juliette/")
    assert_response :success
  end

end
