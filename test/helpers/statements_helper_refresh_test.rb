require 'test_helper'

# StatementsHelper tests for search_cckg() only
class StatementsHelperRefreshTest < ActionView::TestCase
  tests StatementsHelper

  # statement set to manual
  test "should not refresh when manual and ok" do
    stat = statements(:one)
    stat.manual = true
    stat.status = "ok"
    expected = stat.cache_refreshed
    refresh_statement_helper(stat)
    assert_equal expected, stat.cache_refreshed, "Cache refresh dates should NOT have changed"
  end
  
  test "should not refresh when set to manual and status is updated" do
    stat = statements(:one)
    stat.manual = true
    stat.status = "updated"
    expected = stat.cache_refreshed
    refresh_statement_helper(stat)
    assert_equal expected, stat.cache_refreshed, "Cache refresh dates should NOT have changed"
  end

  test "should NOT refresh when manual and problem (meaning flagged)" do
    stat = statements(:one)
    stat.manual = true
    stat.status = "problem"
    expected = stat.cache_refreshed
    refresh_statement_helper(stat)
    assert_not_equal expected, stat.cache_refreshed
  end

  test "should refresh when manual and initial" do
    stat = statements(:one)
    stat.manual = true
    stat.status = "initial"
    expected = stat.cache_refreshed
    refresh_statement_helper(stat)
    assert_not_equal expected, stat.cache_refreshed, "Cache refresh dates should have changed"
  end

  test "should refresh when manual and missing (required property)" do
    stat = statements(:one)
    stat.manual = true
    stat.status = "missing"
    expected = stat.cache_refreshed
    refresh_statement_helper(stat)
    assert_not_equal expected, stat.cache_refreshed, "Cache refresh dates should have changed"
  end

  test "refresh_statement_helper preserves full non-trace run_dsl result" do
    stat = statements(:one)
    run_result = %w[first second]

    self.stubs(:trace_enabled_for_request?).returns(false)
    self.expects(:run_dsl).returns(run_result)
    self.expects(:format_datatype).with(run_result, stat.source.property, stat.webpage).returns("formatted")
    self.stubs(:save_record?).returns(true)

    refresh_statement_helper(stat)

    assert_equal "formatted", stat.reload.cache
  end

  test "refresh_statement_helper adds error when run_dsl aborts" do
    stat = statements(:one)

    self.stubs(:trace_enabled_for_request?).returns(false)
    self.stubs(:run_dsl).returns(["abort_update", { error_type: "SocketError", error: "Wringer unreachable" }])

    refresh_statement_helper(stat)

    assert stat.errors.any?
    assert_includes stat.errors.full_messages.to_sentence, "Scrape aborted (SocketError)"
  end
  
 # 'abort_update' in cache

  test "should refresh when abort_update in crawl data and in cache when status OK" do
    stat = statements(:one)
    stat.cache = 'There is an abort_update'
    stat.status = "ok"
    expected = stat.cache_refreshed
    refresh_statement_helper(stat)
    assert_not_equal expected, stat.cache_refreshed, "Cache refresh dates should have changed"
  end


  
  # save_record?(data_str,stat_status,stat_cache, new_record)
  test "true when data has abort_update" do
    expected = true
    actual = save_record?('There is an abort_update','initial',nil, true)
    assert_equal expected, actual
    actual = save_record?('There is an abort_update','problem','value with problem', false)
    assert_equal expected, actual
    actual = save_record?('There is an abort_update','missing',[], false)
    assert_equal expected, actual
  end

  test "true when data has abort_update and cache has previous abort_update" do
    expected = true
    actual = save_record?('There is an abort_update','ok', 'previous abort_update', false)
    assert_equal expected, actual
    actual = save_record?('There is an abort_update','updated', 'previous abort_update', false)
    assert_equal expected, actual
  end

  test "false when data has abort_update and status is ok or updated" do
    expected = false
    actual = save_record?('There is an abort_update','ok','value to preserve',false)
    assert_equal expected, actual
    actual = save_record?('There is an abort_update','updated','value to preserve', false)
    assert_equal expected, actual
  end

  test "data is blank" do
    expected = true
    actual = save_record?('[]','initial',nil, true)
    assert_equal expected, actual
    actual = save_record?('','ok','previous abort_update', false)
    assert_equal expected, actual
  end

  test "data is blank for existing record status ok" do
    expected = false
    actual = save_record?('','ok','preserve value', false)
    assert_equal expected, actual
    actual = save_record?('','updated','preserve value', false)
    assert_equal expected, actual
  end

  test "true for general case" do
    expected = true
    actual = save_record?('something good','ok','preserve value', false)
    assert_equal expected, actual
    actual = save_record?('something good','updated','previous abort_update', false)
    assert_equal expected, actual
  end

  test "true when data is nil and cache contains abort_update" do
    expected = true
    actual = save_record?(nil,'ok','previous abort_update', false)
    assert_equal expected, actual
  end

  test "true when cache is nil" do
    expected = true
    actual = save_record?(['test','Organization',['Organization','http://test.org']],'ok',nil, false)
    assert_equal expected, actual
  end

  # preserve_manual_links(data, stat.cache)
  test "cache is updated" do
    expected = [['updated org','Organization',['Organization','http://test2.org']]]
    actual = preserve_manual_links(['updated org','Organization',['Organization','http://test2.org']],['updated org','Organization',['Organization','http://test.org']])
    assert_equal expected, actual
  end
  test "cache is updated and manual links preserved" do
    expected = [["updated org", "Organization", ["Organization", "http://test2.org"]], ["Manually added", "Organization", ["Organization", "http://test.org"]]]
    actual = preserve_manual_links(['updated org','Organization',['Organization','http://test2.org']],['Manually added','Organization',['Organization','http://test.org']])
    assert_equal expected, actual
  end
  test "cache is updated when old cache is nil" do
    expected = ['updated org','Organization',['Organization','http://test2.org']]
    actual = preserve_manual_links(['updated org','Organization',['Organization','http://test2.org']],nil)
    assert_equal expected, actual
  end

end
