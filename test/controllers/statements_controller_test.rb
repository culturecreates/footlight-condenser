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

  test "should create statement" do
    assert_difference('Statement.count') do
      #use different combination of webpage_id and source_id
      post statements_url, params: { statement: { cache: @statement.cache, cache_changed: @statement.cache_changed, cache_refreshed: @statement.cache_refreshed, source_id: @statement.source_id, status: @statement.status, status_origin: @statement.status_origin, webpage_id: statements(:two).webpage.id } }
    end

    assert_redirected_to statement_url(Statement.last)
  end

  test "should NOT create statement because duplicate key pair violation in model" do
    assert_difference('Statement.count', 0) do
      post statements_url, params: { statement: { cache: @statement.cache, cache_changed: @statement.cache_changed, cache_refreshed: @statement.cache_refreshed, source_id: @statement.source_id, status: @statement.status, status_origin: @statement.status_origin, webpage_id: @statement.webpage.id } }
    end

  end

  test "should show statement" do
    get statement_url(@statement)
    assert_response :success
  end

  test "should get edit" do
    get edit_statement_url(@statement)
    assert_response :success
  end

  test "should update statement" do
    patch statement_url(@statement),
    params: { statement:
      { cache: @statement.cache,
        cache_changed: @statement.cache_changed,
        cache_refreshed: @statement.cache_refreshed,
        source_id: @statement.source_id,
        status: @statement.status,
        status_origin: @statement.status_origin,
        webpage_id: @statement.webpage_id } }
    assert_redirected_to show_resources_path(rdf_uri: @statement.webpage.rdf_uri)
  end

  test "should destroy statement" do
    assert_difference('Statement.count', -1) do
      delete statement_url(@statement)
    end

    assert_redirected_to statements_url
  end



end
