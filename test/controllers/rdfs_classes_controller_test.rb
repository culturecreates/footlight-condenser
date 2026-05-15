require 'test_helper'

class RdfsClassesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @rdfs_class = rdfs_classes(:one)
  end

  test "should get index" do
    get rdfs_classes_url
    assert_response :success
  end

  test "rdfs classes index renders harmonized table shell and sortable headers" do
    get rdfs_classes_url

    assert_response :success
    assert_select ".harmonized-table-shell", 1
    assert_select 'th a[href*="sort=name"]'
  end

  test "rdfs classes index falls back safely for invalid sort and direction" do
    get rdfs_classes_url, params: { sort: "bogus", direction: "sideways" }

    assert_response :redirect
    assert_redirected_to rdfs_classes_url
  end

  test "rdfs classes index renders empty state" do
    get rdfs_classes_url, params: { term: "no-such-rdfs-class-filter" }

    follow_redirect! if response.redirect?
    assert_response :success
    assert_select ".harmonized-table-empty-state", 1
  end

  test "should get new" do
    get new_rdfs_class_url
    assert_response :success
  end

  test "should create rdfs_class" do
    assert_difference('RdfsClass.count') do
      post rdfs_classes_url, params: { rdfs_class: { name: @rdfs_class.name } }
    end

    assert_redirected_to rdfs_class_url(RdfsClass.last)
  end

  test "should show rdfs_class" do
    get rdfs_class_url(@rdfs_class)
    assert_response :success
  end

  test "rdfs class show renders harmonized card hooks" do
    get rdfs_class_url(@rdfs_class)

    assert_response :success
    assert_select ".harmonized-card-grid", minimum: 1
    assert_select ".harmonized-card", minimum: 1
    assert_select ".harmonized-card-title", minimum: 1
    assert_select ".harmonized-card-value", minimum: 1
    assert_select ".harmonized-card-actions", minimum: 1
  end

  test "should get edit" do
    get edit_rdfs_class_url(@rdfs_class)
    assert_response :success
  end

  test "should update rdfs_class" do
    patch rdfs_class_url(@rdfs_class), params: { rdfs_class: { name: @rdfs_class.name } }
    assert_redirected_to rdfs_class_url(@rdfs_class)
  end

  test "should destroy rdfs_class" do
    assert_difference('RdfsClass.count', -1) do
      delete rdfs_class_url(@rdfs_class)
    end

    assert_redirected_to rdfs_classes_url
  end
end
