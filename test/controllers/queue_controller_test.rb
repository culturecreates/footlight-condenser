require 'test_helper'

class QueueControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get queue_index_url
    assert_response :success
  end

end
