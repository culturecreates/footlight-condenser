require 'test_helper'

class ResourcesControllerTest < ActionDispatch::IntegrationTest
  test "should get event" do
    get show_resources_path(rdf_uri: "one", format: :json)
    assert_response :success
  end
end
