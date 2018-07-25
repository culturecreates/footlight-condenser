require 'test_helper'

class PredicatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @predicate = predicates(:one)
  end

  test "should get index" do
    get predicates_url
    assert_response :success
  end

  test "should get new" do
    get new_predicate_url
    assert_response :success
  end

  test "should create predicate" do
    assert_difference('Predicate.count') do
      post predicates_url, params: { predicate: { label: @predicate.label, language: @predicate.language, object_datatype: @predicate.object_datatype, uri: @predicate.uri } }
    end

    assert_redirected_to predicate_url(Predicate.last)
  end

  test "should show predicate" do
    get predicate_url(@predicate)
    assert_response :success
  end

  test "should get edit" do
    get edit_predicate_url(@predicate)
    assert_response :success
  end

  test "should update predicate" do
    patch predicate_url(@predicate), params: { predicate: { label: @predicate.label, language: @predicate.language, object_datatype: @predicate.object_datatype, uri: @predicate.uri } }
    assert_redirected_to predicate_url(@predicate)
  end

  test "should destroy predicate" do
    assert_difference('Predicate.count', -1) do
      delete predicate_url(@predicate)
    end

    assert_redirected_to predicates_url
  end
end
