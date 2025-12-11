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
      post statements_url, params: { statement: { cache: @statement.cache, cache_changed: @statement.cache_changed, cache_refreshed: @statement.cache_refreshed, source_id: @statement.source_id, status: @statement.status, status_origin: @statement.status_origin, webpage_id: statements(:three).webpage.id } }
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
    assert_redirected_to statements_path(rdf_uri: @statement.webpage.rdf_uri)
  end

  test "should REFRESH webpage" do
    patch refresh_webpage_statements_path(url: webpages(:six).url)
    assert_redirected_to webpage_statements_path(url: webpages(:six).url)
  end

  test "should destroy statement" do
    assert_difference('Statement.count', -1) do
      delete statement_url(@statement)
    end

    assert_redirected_to statements_url
  end

  test "should update statements by adding link" do  
    statement_params = { "statement": {"cache": "[\"name1\",\"class1\",\"uri1\"]", "status": "ok", "status_origin": "test_user"} }
    patch add_linked_data_statement_url(statements(:four)), params: statement_params
    assert_redirected_to show_resources_path(rdf_uri: statements(:four).webpage.rdf_uri)
  
  end


  test "should update statements by adding link when cache is blank" do  
    statement_params = { "statement": {"cache": "[\"name1\",\"class1\",\"uri1\"]", "status": "ok", "status_origin": "test_user"} }

    patch add_linked_data_statement_url(statements(:blankCache)), params: statement_params
    assert_redirected_to show_resources_path(rdf_uri: statements(:blankCache).webpage.rdf_uri)
  
  end


  test "should update statements with double array by adding link" do  
    statement_params = { "statement": {"cache": "[\"name1\",\"class1\",\"uri1\"]", "status": "ok", "status_origin": "test_user"} }
    patch add_linked_data_statement_url(statements(:five)), params: statement_params
    assert_redirected_to show_resources_path(rdf_uri: statements(:five).webpage.rdf_uri)
  end

  test "should update statements by removing link in statement" do  
    statement_params = { "statement": {"cache": "[\"name1\",\"class1\",\"uri1\"]", "status": "ok", "status_origin": "test_user"} }
    patch remove_linked_data_statement_url(statements(:five)), params: statement_params
    assert_redirected_to show_resources_path(rdf_uri: statements(:five).webpage.rdf_uri)
  end


  test "should activate source of statements" do
    patch activate_statement_path(@statement)
    assert_redirected_to statements_path(rdf_uri: "uri1")

    patch activate_statement_path(@statement, params: {format: :json})
    assert_redirected_to show_resources_path(rdf_uri: "uri1.json")
  end



end
