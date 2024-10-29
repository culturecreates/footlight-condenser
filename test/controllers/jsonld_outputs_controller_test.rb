require 'test_helper'

class JsonldOutputsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @jsonld_output = jsonld_outputs(:one)
  end

  test "should get index" do
    get jsonld_outputs_url
    assert_response :success
  end

  test "should get new" do
    get new_jsonld_output_url
    assert_response :success
  end

  test "should create jsonld_output" do
    assert_difference('JsonldOutput.count') do
      post jsonld_outputs_url, params: { jsonld_output: { name: @jsonld_output.name , frame: @jsonld_output.frame } }
    end

    assert_redirected_to jsonld_output_url(JsonldOutput.last)
  end

  test "should show jsonld_output" do
    get jsonld_output_url(@jsonld_output)
    assert_response :success
  end

  test "should get edit" do
    get edit_jsonld_output_url(@jsonld_output)
    assert_response :success
  end

  test "should update jsonld_output" do
    patch jsonld_output_url(@jsonld_output), params: { jsonld_output: { name: @jsonld_output.name } }
    assert_redirected_to jsonld_output_url(@jsonld_output)
  end

  test "should destroy jsonld_output" do
    assert_difference('JsonldOutput.count', -1) do
      delete jsonld_output_url(@jsonld_output)
    end

    assert_redirected_to jsonld_outputs_url
  end
end
