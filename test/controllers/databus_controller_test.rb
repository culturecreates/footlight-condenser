require 'test_helper'

class DatabusControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get databus_index_url
    assert_response(:success, message: "To laod credentials >source .aws_keys")
  end


end
