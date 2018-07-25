require 'test_helper'

class ObjectClassesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @object_class = object_classes(:one)
  end

  test "should get index" do
    get object_classes_url
    assert_response :success
  end

  test "should get new" do
    get new_object_class_url
    assert_response :success
  end

  test "should create object_class" do
    assert_difference('ObjectClass.count') do
      post object_classes_url, params: { object_class: { name: @object_class.name } }
    end

    assert_redirected_to object_class_url(ObjectClass.last)
  end

  test "should show object_class" do
    get object_class_url(@object_class)
    assert_response :success
  end

  test "should get edit" do
    get edit_object_class_url(@object_class)
    assert_response :success
  end

  test "should update object_class" do
    patch object_class_url(@object_class), params: { object_class: { name: @object_class.name } }
    assert_redirected_to object_class_url(@object_class)
  end

  test "should destroy object_class" do
    assert_difference('ObjectClass.count', -1) do
      delete object_class_url(@object_class)
    end

    assert_redirected_to object_classes_url
  end
end
