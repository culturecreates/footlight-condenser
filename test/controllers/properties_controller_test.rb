require 'test_helper'

class PropertiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @property = properties(:one)
  end

  test "should get index" do
    get properties_url
    assert_response :success
  end

  test "properties index renders harmonized table shell and sortable headers" do
    get properties_url

    assert_response :success
    assert_select ".harmonized-table-shell", 1
    assert_select 'th a[href*="sort=label"]'
    assert_select 'th a[href*="sort=uri"]'
  end

  test "properties index falls back safely for invalid sort and direction" do
    get properties_url, params: { sort: "bogus", direction: "sideways" }

    assert_response :redirect
    assert_redirected_to properties_url
  end

  test "properties index renders empty state" do
    get properties_url, params: { term: "no-such-property-filter" }

    follow_redirect! if response.redirect?
    assert_response :success
    assert_select ".harmonized-table-empty-state", 1
  end

  test "should get new" do
    get new_property_url
    assert_response :success
  end

  test "should create property" do
    assert_difference('Property.count') do
      post properties_url, params: { property: { label: @property.label,  rdfs_class_id: @property.rdfs_class_id, uri: @property.uri, value_datatype: @property.value_datatype } }
    end

    assert_redirected_to property_url(Property.last)
  end

  test "should show property" do
    get property_url(@property)
    assert_response :success
  end

  test "property show renders harmonized card hooks" do
    get property_url(@property)

    assert_response :success
    assert_select ".harmonized-card-grid", minimum: 1
    assert_select ".harmonized-card", minimum: 1
    assert_select ".harmonized-card-title", minimum: 1
    assert_select ".harmonized-card-value", minimum: 1
    assert_select ".harmonized-card-actions", minimum: 1
  end

  test "should get edit" do
    get edit_property_url(@property)
    assert_response :success
  end

  test "should update property" do
    patch property_url(@property), params: { property: { label: @property.label, rdfs_class_id: @property.rdfs_class_id, uri: @property.uri, value_datatype: @property.value_datatype } }
    assert_redirected_to property_url(@property)
  end

  test "should destroy property" do
    assert_difference('Property.count', -1) do
      delete property_url(@property)
    end

    assert_redirected_to properties_url
  end
end
