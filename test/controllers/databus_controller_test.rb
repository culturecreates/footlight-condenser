require 'test_helper'

class DatabusControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get databus_index_url
    assert_response(:success, message: "To load credentials >source .aws_keys")
  end

  test "should call artsdata databus api with missing params" do
    post databus_artsdata_url
    assert_response(:success)
  end

  test "should call artsdata databus api with bad file" do
    post databus_artsdata_url(group: "footlight", artifact: "test", version:"1.2.3",downloadUrl: 'http://culturecreates.com', downloadFile:"test.json")
    assert_response(:success)
  end

  test "should call artsdata databus api with good params" do
    post databus_artsdata_url(group: "footlight", artifact: "mytest.com", version:"1.2.3",downloadUrl: 'https://data.culturecreates.com/databus/culture-creates/footlight/mytest.com/1.2.3/export.json', downloadFile:"export.json")
    assert_response(:success)
  end

end
