require 'test_helper'

class DatabusControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get databus_index_url
    assert_response :success
  end

  test "should get create" do
    get databus_create_url
    assert_response :success
  end

end
