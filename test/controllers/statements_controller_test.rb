require 'test_helper'

class StatementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @statement = statements(:one)
  end

  test "should get index" do
    get statements_url
    assert_response :success
  end

  test "should get new" do
    get new_statement_url
    assert_response :success
  end

  # test "should create statement" do
  #   assert_difference('Statement.count') do
  #     post statements_url, params: { statement: { cache: @statement.cache, cache_changed: @statement.cache_changed, cache_refreshed: @statement.cache_refreshed, property_id: @statement.property_id, status: @statement.status, status_origin: @statement.status_origin, webpage_id: @statement.webpage_id } }
  #   end
  #
  #   assert_redirected_to statement_url(Statement.last)
  # end

  test "should show statement" do
    get statement_url(@statement)
    assert_response :success
  end

  test "should get edit" do
    get edit_statement_url(@statement)
    assert_response :success
  end

  test "should update statement" do
    patch statement_url(@statement), params: { statement: { cache: @statement.cache, cache_changed: @statement.cache_changed, cache_refreshed: @statement.cache_refreshed, property_id: @statement.property_id, status: @statement.status, status_origin: @statement.status_origin, webpage_id: @statement.webpage_id } }
    assert_redirected_to statement_url(@statement)
  end

  test "should destroy statement" do
    assert_difference('Statement.count', -1) do
      delete statement_url(@statement)
    end

    assert_redirected_to statements_url
  end

  test "should scrape title from html" do
    @controller = StatementsController.new
    source = sources(:one)
    source.algorithm_value = "xpath=//title"
    expected_output = ['Culture Creates | Digital knowledge management for the arts']
    assert_equal expected_output, @controller.instance_eval{helpers.scrape(source, "http://culturecreates.com")}
  end

  test "should covert url for wringer" do
    @controller = StatementsController.new
    expected_output = "http://footlight-wringer.herokuapp.com/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true"
    assert_equal expected_output, @controller.instance_eval{helpers.use_wringer("http://culturecreates.com", false)}
  end

  test "should covert url for wringer using phantomjs" do
    @controller = StatementsController.new
    expected_output = "http://footlight-wringer.herokuapp.com/websites/wring?uri=http%3A%2F%2Fculturecreates.com&format=raw&include_fragment=true&use_phantomjs=true"
    assert_equal expected_output, @controller.instance_eval{helpers.use_wringer("http://culturecreates.com", true)}
  end

  test "should covert french date from webpage into ISO date" do
    @controller = StatementsController.new
    expected_output = "2018-08-02"
    assert_equal expected_output, @controller.instance_eval{helpers.ISO_date("le jeudi 2 août 2018")}
  end

  test "should covert english date from webpage into ISO date" do
    @controller = StatementsController.new
    expected_output = "2018-08-02"
    assert_equal expected_output, @controller.instance_eval{helpers.ISO_date("Thursday, August 2, 2018")}
  end

  # test "should scrape 2 items from html" do
  #   @controller = StatementsController.new
  #   source = OpenStruct.new(algorithm_value: 'xpath=//title,xpath=//h3')
  #   expected_output = ['Culture Creates | Digital knowledge management for the arts']
  #   assert_equal expected_output, @controller.instance_eval{scrape(source, "http://culturecreates.com", nil)}
  # end

end
