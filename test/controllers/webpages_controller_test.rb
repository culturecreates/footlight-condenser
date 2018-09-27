require 'test_helper'

class WebpagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @webpage = webpages(:one)
  end

  test "should get index" do
    get webpages_url
    assert_response :success
  end

  test "should get new" do
    get new_webpage_url
    assert_response :success
  end

  test "should create webpage" do
    assert_difference('Webpage.count') do
      post webpages_url, params: { webpage: { language: @webpage.language, rdf_uri: @webpage.rdf_uri, rdfs_class_id: @webpage.rdfs_class_id, url: @webpage.url + "newwebpageurl", website_id: @webpage.website_id } }
    end

    assert_redirected_to webpage_url(Webpage.last)
  end

  test "should show webpage" do
    get webpage_url(@webpage)
    assert_response :success
  end

  test "should get edit" do
    get edit_webpage_url(@webpage)
    assert_response :success
  end

  test "should update webpage" do
    patch webpage_url(@webpage), params: { webpage: { language: @webpage.language, rdf_uri: @webpage.rdf_uri, rdfs_class_id: @webpage.rdfs_class_id, url: @webpage.url, website_id: @webpage.website_id } }
    assert_redirected_to webpage_url(@webpage)
  end

  test "should destroy webpage" do
    assert_difference('Webpage.count', -1) do
      delete webpage_url(@webpage)
    end

    assert_redirected_to webpages_url
  end
end
