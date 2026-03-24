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
    self.stubs(:trace_enabled_for_request?).returns(false)
    self.stubs(:run_dsl).returns(["fresh data"])
    self.stubs(:format_datatype).returns("formatted")
    self.stubs(:save_record?).returns(true)
    refresh_statement_helper(stat)
    assert_not_equal expected, stat.cache_refreshed
  end

  test "should refresh when manual and initial" do
    stat = statements(:one)
    stat.manual = true
    stat.status = "initial"
    expected = stat.cache_refreshed
    self.stubs(:trace_enabled_for_request?).returns(false)
    self.stubs(:run_dsl).returns(["fresh data"])
    self.stubs(:format_datatype).returns("formatted")
    self.stubs(:save_record?).returns(true)
    refresh_statement_helper(stat)
    assert_not_equal expected, stat.cache_refreshed, "Cache refresh dates should have changed"
  end

  test "should refresh when manual and missing (required property)" do
    stat = statements(:one)
    stat.manual = true
    stat.status = "missing"
    expected = stat.cache_refreshed
    self.stubs(:trace_enabled_for_request?).returns(false)
    self.stubs(:run_dsl).returns(["fresh data"])
    self.stubs(:format_datatype).returns("formatted")
    self.stubs(:save_record?).returns(true)
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

  test "refresh_statement_helper short-circuits on abort_update without formatting or saving" do
    stat = statements(:one)
    original_cache = stat.cache
    original_cache_refreshed = stat.cache_refreshed

    self.stubs(:trace_enabled_for_request?).returns(false)
    self.stubs(:run_dsl).returns(["abort_update", { error_type: "SocketError", error: "Wringer unreachable" }])
    self.expects(:format_datatype).never
    self.expects(:save_record?).never

    result = refresh_statement_helper(stat)

    assert_match(/Scrape aborted \(SocketError\)/, result[:errors].join(" "))
    assert_equal original_cache, stat.reload.cache
    assert_equal original_cache_refreshed, stat.cache_refreshed
  end

  test "blank DSL result produces explicit error" do
    stat = statements(:one)

    self.stubs(:trace_enabled_for_request?).returns(false)
    self.stubs(:run_dsl).returns(nil)

    result = refresh_statement_helper(stat)

    assert result[:errors].any?
    assert_includes result[:errors].join, "blank result"
  end

  test "blank DSL result with trace still returns trace and error" do
    stat = statements(:one)

    cookies[:dsl_trace] = "true"
    self.stubs(:run_dsl).returns([nil, [{ step: 1, type: "xpath" }]])

    result = refresh_statement_helper(stat)

    assert result[:errors].any?
    assert result[:trace].present?
  end

  test "run_dsl returning unexpected shape still preserves error and safe trace" do
    stat = statements(:one)

    cookies[:dsl_trace] = "true"
    self.stubs(:run_dsl).returns(nil)

    result = refresh_statement_helper(stat)

    assert result[:errors].any?
    assert_equal [], result[:trace]
  end

  test "refresh_statement_helper returns structured result with trace when dsl_trace cookie is enabled" do
    stat = statements(:one)
    run_result = ["first"]
    trace_events = [{ step: 1, type: "xpath" }]

    cookies[:dsl_trace] = "true"

    self.expects(:run_dsl).with(
      algorithm: stat.source.algorithm_value,
      render_js: stat.source.render_js,
      language: stat.source.language,
      url: stat.webpage.url,
      scrape_options: {},
      trace: true
    ).returns([run_result, trace_events])
    self.expects(:format_datatype).with(run_result, stat.source.property, stat.webpage).returns("formatted")
    self.stubs(:save_record?).returns(true)

    returned_result = refresh_statement_helper(stat)

    assert_equal trace_events, instance_variable_get(:@dsl_trace)
    assert_equal run_result, returned_result[:data]
    assert_equal trace_events, returned_result[:trace]
    assert_equal [], returned_result[:errors]
  end

  test "refresh_statement_helper returns structured result with nil trace when cookie is disabled" do
    stat = statements(:one)
    run_result = ["first"]

    cookies[:dsl_trace] = "false"

    self.expects(:run_dsl).with(
      algorithm: stat.source.algorithm_value,
      render_js: stat.source.render_js,
      language: stat.source.language,
      url: stat.webpage.url,
      scrape_options: {},
      trace: false
    ).returns(run_result)
    self.expects(:format_datatype).with(run_result, stat.source.property, stat.webpage).returns("formatted")
    self.stubs(:save_record?).returns(true)

    returned_result = refresh_statement_helper(stat)

    assert_equal run_result, returned_result[:data]
    assert_nil returned_result[:trace]
    assert_equal [], returned_result[:errors]
    assert_nil instance_variable_get(:@dsl_trace)
  end

  test "run_dsl returns [result, trace] when trace is enabled" do
    runner = mock("dsl_runner")
    runner.expects(:run).with("manual=hello").returns(["hello"])

    Dsl::DslAlgorithmRunner.expects(:new).with do |ctx|
      assert_equal "https://example.com", ctx[:url]
      assert_equal false, ctx[:render_js]
      assert_equal({}, ctx[:scrape_options])
      assert_instance_of Dsl::DslTraceCollector, ctx[:tracer]
      true
    end.returns(runner)

    assert_equal [["hello"], []], run_dsl(algorithm: "manual=hello", url: "https://example.com", trace: true)
  end

  test "run_dsl returns result only when trace is disabled" do
    runner = mock("dsl_runner")
    runner.expects(:run).with("manual=hello").returns(["hello"])

    Dsl::DslAlgorithmRunner.expects(:new).with do |ctx|
      assert_equal "https://example.com", ctx[:url]
      assert_equal false, ctx[:render_js]
      assert_equal({}, ctx[:scrape_options])
      assert_instance_of Dsl::DslNullTracer, ctx[:tracer]
      true
    end.returns(runner)

    assert_equal ["hello"], run_dsl(algorithm: "manual=hello", url: "https://example.com", trace: false)
  end

  test "trace_enabled_for_request? has no implicit fallback" do
    self.stubs(:cookies).raises(NoMethodError, "cookies unavailable")

    assert_raises(NoMethodError) do
      trace_enabled_for_request?
    end
  end
  
 # 'abort_update' in cache

  test "should not refresh when abort_update in crawl data and in cache when status OK" do
    stat = statements(:one)
    stat.cache = 'There is an abort_update'
    stat.status = "ok"
    expected = stat.cache_refreshed
    self.stubs(:trace_enabled_for_request?).returns(false)
    self.stubs(:run_dsl).returns(["abort_update", { error_type: "SocketError", error: "Wringer unreachable" }])
    refresh_statement_helper(stat)
    assert_equal expected, stat.cache_refreshed, "Cache refresh dates should NOT have changed"
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
