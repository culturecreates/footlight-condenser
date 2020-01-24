require 'test_helper'

class SearchExceptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @search_exception = search_exceptions(:one)
  end

  test "should get index" do
    get search_exceptions_url
    assert_response :success
  end

  test "should get new" do
    get new_search_exception_url
    assert_response :success
  end

  test "should create search_exception" do
    assert_difference('SearchException.count') do
      post search_exceptions_url, params: { search_exception: { name: @search_exception.name, rdfs_class_id: @search_exception.rdfs_class_id } }
    end

    assert_redirected_to search_exception_url(SearchException.last)
  end

  test "should show search_exception" do
    get search_exception_url(@search_exception)
    assert_response :success
  end

  test "should get edit" do
    get edit_search_exception_url(@search_exception)
    assert_response :success
  end

  test "should update search_exception" do
    patch search_exception_url(@search_exception), params: { search_exception: { name: @search_exception.name, rdfs_class_id: @search_exception.rdfs_class_id } }
    assert_redirected_to search_exception_url(@search_exception)
  end

  test "should destroy search_exception" do
    assert_difference('SearchException.count', -1) do
      delete search_exception_url(@search_exception)
    end

    assert_redirected_to search_exceptions_url
  end
end
