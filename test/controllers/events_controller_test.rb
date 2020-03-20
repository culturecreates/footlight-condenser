require 'test_helper'

class EventsControllerTest < ActionDispatch::IntegrationTest


  test "should get index for upcoming" do
    get website_events_path(seedurl: "one", format: :json)
    assert_response :success
  end


end
