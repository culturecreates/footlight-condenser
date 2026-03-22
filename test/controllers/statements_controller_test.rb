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

  test "show does not execute trace rendering even when dsl_trace cookie is set" do
    get statement_url(@statement), headers: { "Cookie" => "dsl_trace=true" }
    assert_response :success
    assert_no_match(/Algorithm Trace/, response.body)
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

  test "success with trace shows notice and trace on redirected show page" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect!
    assert_response :success
    assert_match(/Statement was successfully refreshed\./, response.body)
    assert_no_match(/Statement Error:/, response.body)
    assert_match(/Algorithm Trace/, response.body)
    assert_match(/Step 1/, response.body)
    assert_match(/\(manual\)/, response.body)
    assert_match(/Traceable value/, response.body)
    assert_nil session[:dsl_trace]
  end

  test "success without trace shows notice and does not render trace on redirected show page" do
    @statement.source.update!(algorithm_value: "manual=No Trace")

    patch refresh_statement_path(@statement)
    assert_redirected_to statement_url(@statement)
    assert_nil session[:dsl_trace]

    follow_redirect!
    assert_response :success
    assert_match(/Statement was successfully refreshed\./, response.body)
    assert_no_match(/Statement Error:/, response.body)
    assert_no_match(/Algorithm Trace/, response.body)
    assert_nil session[:dsl_trace]
  end

  test "error with trace shows alert and keeps trace rendering" do
    @statement.source.update!(algorithm_value: "ruby=$array.each {|a| a")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect!
    assert_response :success
    assert_match(/Statement Error:/, response.body)
    assert_no_match(/Statement was successfully refreshed\./, response.body)
    assert_error_alert_if_present
    assert_match(/Algorithm Trace/, response.body)
    assert_match(/trace-error/, response.body)
    assert_match(/⚠/, response.body)
    assert_match(/SyntaxError/, response.body)
    body = response.body
    assert body.index("Statement Error") < body.index("Algorithm Trace")
    assert_nil session[:dsl_trace]
  end

  test "error without trace shows alert and no trace rendering" do
    @statement.source.update!(algorithm_value: "ruby=$array.each {|a| a")

    patch refresh_statement_path(@statement)
    assert_redirected_to statement_url(@statement)
    assert_nil session[:dsl_trace]

    follow_redirect!
    assert_response :success
    assert_match(/Statement Error:/, response.body)
    assert_no_match(/Statement was successfully refreshed\./, response.body)
    assert_error_alert_if_present
    assert_no_match(/Algorithm Trace/, response.body)
    assert_match(/SyntaxError/, response.body)
    assert_nil session[:dsl_trace]
  end

  test "error without trace is visible in view" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: nil,
      trace: nil,
      errors: ["boom"]
    )
    StatementsController.any_instance.stubs(:helpers).returns(helper_proxy)

    patch refresh_statement_path(@statement)
    assert_redirected_to statement_url(@statement)
    assert_nil session[:dsl_trace]

    follow_redirect!
    assert_response :success
    assert_match(/Statement Error: boom/, response.body)
    assert_no_match(/Statement was successfully refreshed\./, response.body)
    assert_error_alert_if_present
    assert_no_match(/Algorithm Trace/, response.body)
    assert_nil session[:dsl_trace]
  end

  test "error and trace both visible" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: nil,
      trace: [{ step: 1, type: "ruby", input: ["in"], output: ["out"] }],
      errors: ["boom"]
    )
    StatementsController.any_instance.stubs(:helpers).returns(helper_proxy)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect!
    assert_response :success
    assert_match(/Statement Error: boom/, response.body)
    assert_no_match(/Statement was successfully refreshed\./, response.body)
    assert_error_alert_if_present
    assert_match(/Algorithm Trace/, response.body)
    body = response.body
    assert body.index("Statement Error") < body.index("Algorithm Trace")
    assert_nil session[:dsl_trace]
  end

  test "error is not swallowed when trace is present" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: nil,
      trace: [{ step: 1, type: "ruby", input: ["in"], output: ["out"] }],
      errors: ["critical failure"]
    )
    StatementsController.any_instance.stubs(:helpers).returns(helper_proxy)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect!
    assert_response :success
    assert_match(/Statement Error: critical failure/, response.body)
    assert_no_match(/Statement was successfully refreshed\./, response.body)
    assert_error_alert_if_present
    assert_match(/Algorithm Trace/, response.body)
    body = response.body
    assert body.index("Statement Error") < body.index("Algorithm Trace")
    assert_nil session[:dsl_trace]
  end

  test "empty trace still shows error" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: nil,
      trace: [],
      errors: ["failure"]
    )
    StatementsController.any_instance.stubs(:helpers).returns(helper_proxy)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    assert_redirected_to statement_url(@statement)
    trace = session[:dsl_trace].with_indifferent_access
    assert_equal 2, trace[:version]
    assert_equal [], trace[:steps]

    follow_redirect!
    assert_response :success
    assert_match(/Statement Error: failure/, response.body)
    assert_no_match(/Statement was successfully refreshed\./, response.body)
    assert_error_alert_if_present
    assert_match(/Algorithm Trace/, response.body)
    body = response.body
    assert body.index("Statement Error") < body.index("Algorithm Trace")
    assert_nil session[:dsl_trace]
  end

  test "refresh stores formatted trace in session" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    assert_redirected_to statement_url(@statement)

    assert_nil flash[:dsl_trace]
    trace = assert_session_trace_present_and_structured

    first = trace[:steps].first.with_indifferent_access
    assert_equal 1, first[:s]
    assert_equal "manual", first[:t]

    follow_redirect!
    assert_response :success
    assert_nil session[:dsl_trace]
  end

  test "show retrieves trace after redirect and clears session trace" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect!
    assert_response :success
    assert_match(/Algorithm Trace/, response.body)
    assert_nil session[:dsl_trace]
  end

  test "helper contract returns structured result" do
    helpers = Class.new do
      include StatementsHelper

      def cookies
        @cookies ||= {}
      end
    end.new

    helpers.stubs(:run_dsl).returns("contract value")
    helpers.stubs(:format_datatype).returns("contract value")
    helpers.stubs(:save_record?).returns(false)

    result = helpers.refresh_statement_helper(@statement)

    assert result.is_a?(Hash)
    assert result.key?(:data)
    assert result.key?(:trace)
    assert result.key?(:errors)
    assert result[:errors].is_a?(Array)
  end

  test "trace does not appear when trace is nil" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).returns(
      data: nil,
      trace: nil,
      errors: []
    )
    StatementsController.any_instance.stubs(:helpers).returns(helper_proxy)

    patch refresh_statement_path(@statement)
    assert_redirected_to statement_url(@statement)
    assert_nil session[:dsl_trace]

    follow_redirect!
    assert_response :success
    assert_no_match(/Algorithm Trace/, response.body)
  end

  test "error step is always visible even with large trace" do
    large_trace = (1..10).map do |i|
      {
        step: i,
        type: "ruby",
        code: "x" * 1000,
        input: ["y" * 1000],
        output: ["z" * 1000]
      }
    end

    large_trace.last[:error_class] = "NoMethodError"
    large_trace.last[:error_message] = "boom"

    stub_helper_with_trace(large_trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    body = response.body

    assert_match /Algorithm Trace/, body
    assert_match /NoMethodError/, body
  end

  test "all trace steps are preserved in session and rendered" do
    trace = (1..10).map do |i|
      { step: i, type: "ruby" }
    end

    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }

    assert_equal 10, session[:dsl_trace].with_indifferent_access[:steps].size

    follow_redirect!

    (1..10).each do |i|
      assert_match /Step #{i}/, response.body
    end
  end

  test "trace displays state transitions instead of table" do
    trace = [
      { step: 1, type: "ruby", input_preview: ["one"], output_preview: ["two"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/Algorithm Trace/, response.body)
    assert_match(/→/, response.body)
    assert_no_match(/<table/, response.body)
  end

  test "array summary shows content in trace viewer" do
    trace = [
      {
        step: 1,
        type: "ruby",
        input_preview: ["https://example.com/a/really/long/path", "2026-01-01", "extra"],
        output_preview: ["https://example.com/" + ("z" * 90), "done", "extra2"]
      }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/\[\d+ items:/, response.body)
    assert_match(/https:\/\/example.com/, response.body)
    assert_no_match(/extra2/, response.body)
    assert_no_match(/z{70}/, response.body)
  end

  test "code is truncated in trace viewer" do
    trace = [
      {
        step: 1,
        type: "ruby",
        code: "x" * 500,
        input_preview: ["in"],
        output_preview: ["out"]
      }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    displayed_code = response.body[/<div class="trace-code">\s*<code>\s*<span[^>]*>([^<]+)<\/span>\s*<\/code>/m, 1]
    assert displayed_code.present?
    assert_operator displayed_code.length, :<=, 80
    assert_match(/x{20}/, displayed_code)
    assert_no_match(/x{150}/, displayed_code)
    assert_match(/title="/, response.body)
  end

  test "xpath step is classified as extraction" do
    trace = [{ step: 1, type: "xpath", code: "//div", output_preview: [] }]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/extraction/, response.body)
  end

  test "ruby reject is classified as filter" do
    trace = [
      { step: 1, type: "ruby", code: "$array.map{}", output_preview: ["A"] },
      { step: 2, type: "ruby", code: "$array.reject{}", output_preview: ["B"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/filter \(Δ changed\)/, response.body)
  end

  test "tooltip contains full rendered code value" do
    trace = [{ step: 1, type: "ruby", code: "alpha_beta", output_preview: [] }]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/title="/, response.body)
    assert_match(/alpha_beta/, response.body)
  end

  test "error marker is visible in trace viewer" do
    trace = [
      {
        step: 1,
        type: "ruby",
        code: "bad",
        error_class: "NoMethodError",
        error_message: "boom"
      }
    ]
    stub_helper_with_trace(trace, errors: ["boom"])

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/⚠/, response.body)
    assert_match(/NoMethodError/, response.body)
  end

  test "delta shows added elements in array" do
    trace = [
      { step: 1, type: "ruby", output_preview: [] },
      { step: 2, type: "ruby", output_preview: ["A"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/Δ added/, response.body)
    assert_no_match(/class="trace-delta"/, response.body)
  end

  test "delta shows removed elements in array" do
    trace = [
      { step: 1, type: "ruby", output_preview: ["A", "B"] },
      { step: 2, type: "ruby", output_preview: ["A"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/Δ changed/, response.body)
    assert_match(/-B/, response.body)
  end

  test "delta remains visible even when values are truncated" do
    long_url = "https://example.com/" + ("x" * 200)

    trace = [
      { step: 1, type: "ruby", output_preview: ["seed"] },
      { step: 2, type: "ruby", output_preview: [long_url] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/Δ changed/, response.body)
    assert_match(/\+https:\/\/example.com/, response.body)
  end

  test "no delta shown when state unchanged" do
    trace = [
      { step: 1, type: "ruby", output_preview: ["A"] },
      { step: 2, type: "ruby", output_preview: ["A"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/No change/, response.body)
    assert_no_match(/class="trace-delta"/, response.body)
  end

  test "no change is rendered when consecutive outputs are identical" do
    trace = [
      { step: 1, type: "ruby", output_preview: ["A"] },
      { step: 2, type: "ruby", output_preview: ["A"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/No change/, response.body)
  end

  test "no result is rendered when output stays empty" do
    trace = [
      { step: 1, type: "ruby", output_preview: [] },
      { step: 2, type: "ruby", output_preview: [] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/No result/, response.body)
  end

  test "exactly one semantic label is rendered per step" do
    trace = [
      { step: 1, type: "ruby", output_preview: [] },
      { step: 2, type: "ruby", output_preview: ["A"] },
      { step: 3, type: "ruby", output_preview: ["B"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_equal 3, response.body.scan(/class="trace-semantic"/).size
  end

  test "output is always shown even when empty array" do
    trace = [
      { step: 1, type: "ruby", output_preview: [] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/→\s*\[\]/, response.body)
  end

  test "input is not shown when output is empty array" do
    trace = [
      { step: 1, type: "ruby", input_preview: ["INPUT_ONLY_MARKER"], output_preview: [] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match(/→\s*\[\]/, response.body)
    assert_no_match(/→\s*INPUT_ONLY_MARKER/, response.body)
  end

  test "compact trace urls are reconstructed correctly in view" do
    trace = [
      { step: 1, type: "ruby", url_before: "http://example.com/a", url_after: "http://example.com/b" },
      { step: 2, type: "ruby", url_before: "http://example.com/a", url_after: "http://example.com/b" }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    compact = session[:dsl_trace].with_indifferent_access
    assert_equal "http://example.com/a", compact[:initial].with_indifferent_access[:url]
    assert_equal ["http://example.com/b"], compact[:urls]

    follow_redirect!
    assert_match(/http:\/\/example.com\/b/, response.body)
  end

  test "v2 step chain reconstruction uses previous output as next input" do
    compact = {
      version: 2,
      initial: { state: "seed", url: "http://example.com/start" },
      urls: ["http://example.com/next"],
      steps: [
        { s: 1, t: "ruby", o: "state-1", ua: 0 },
        { s: 2, t: "ruby", o: "state-2" }
      ]
    }

    expanded = StatementsController.new.expand_trace_for_view(compact)

    assert_equal "seed", expanded.first[:input]
    assert_equal "state-1", expanded.first[:output]
    assert_equal "state-1", expanded.second[:input]
    assert_equal "state-2", expanded.second[:output]
  end

  test "expand_trace_for_view supports v1 compact format for backward compatibility" do
    compact_v1 = {
      version: 1,
      urls: ["http://example.com/a", "http://example.com/b"],
      events: [{ s: 1, t: "ruby", i: "in", o: "out", ub: 0, ua: 1, d: 1.0, e: "boom" }]
    }

    expanded = StatementsController.new.expand_trace_for_view(compact_v1)
    first = expanded.first.with_indifferent_access

    assert_equal 1, first[:step]
    assert_equal "ruby", first[:type]
    assert_equal "in", first[:input]
    assert_equal "out", first[:output]
    assert_equal "http://example.com/a", first[:url_before]
    assert_equal "http://example.com/b", first[:url_after]
    assert_equal "boom", first[:error]
  end

  test "trace storage does not trigger CookieOverflow" do
    large_trace = build_large_realistic_trace(20)
    stub_helper_with_trace(large_trace)

    assert_nothing_raised do
      patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    end

    trace = assert_session_trace_present_and_structured
    assert_equal 20, trace[:steps].size
    assert_operator Marshal.dump(session.to_hash).bytesize, :<, 3000
  end

  test "overflow trace still preserves error visibility" do
    trace = build_large_realistic_trace(20)
    trace.last[:error_class] = "NoMethodError"
    trace.last[:error_message] = "boom"

    stub_helper_with_trace(trace, errors: ["boom"])

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    follow_redirect!

    assert_match /Statement Error:/, response.body
  end

  test "large trace payload does not overflow cookies because trace is truncated for session" do
    large_trace = [
      {
        step: 1,
        type: "ruby",
        code: "x" * 10_000,
        input_preview: ["in"],
        output_preview: ["out"],
        error_class: nil,
        error_message: nil,
        url_before: "http://example.com",
        url_after: "http://example.com",
        duration_ms: 1.0
      }
    ]

    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(data: nil, trace: large_trace, errors: [])
    helper_proxy.expects(:instance_variable_get).never
    StatementsController.any_instance.stubs(:helpers).returns(helper_proxy)

    assert_nothing_raised do
      patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true" }
    end

    assert_redirected_to statement_url(@statement)
    assert_nil flash[:dsl_trace]
    trace = assert_session_trace_present_and_structured
    first = trace[:steps].first.with_indifferent_access
    assert first.key?(:s)
    assert first.key?(:t)
    assert first.key?(:o)
    assert_operator JSON.generate(trace).bytesize, :<, 3500
    assert_operator Marshal.dump(session.to_hash).bytesize, :<, 3000

    follow_redirect!
    assert_response :success
    assert_nil session[:dsl_trace]
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



  private

  def assert_error_alert_if_present
    return unless response.body.match?(/class=(['"])[^'"]*\balert\b[^'"]*\1/)

    assert_select ".alert", /Statement Error:/
  end

  def stub_helper_with_trace(trace, errors: [])
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: nil,
      trace: trace,
      errors: errors
    )
    StatementsController.any_instance.stubs(:helpers).returns(helper_proxy)
  end

  def build_large_realistic_trace(n)
    (1..n).map do |i|
      {
        step: i,
        type: "ruby",
        code: "x" * 1000,
        input_preview: ["y" * 1000],
        output_preview: ["z" * 1000],
        url_before: "http://example.com",
        url_after: "http://example.com",
        duration_ms: 1.0
      }
    end
  end

  def assert_session_trace_present_and_structured
    trace = session[:dsl_trace]
    assert trace.present?
    assert trace.is_a?(Hash)

    compact = trace.with_indifferent_access
    assert_equal 2, compact[:version]
    assert compact[:initial].is_a?(Hash)
    assert compact[:urls].is_a?(Array)
    assert compact[:steps].is_a?(Array)
    assert compact[:steps].present?

    first = compact[:steps].first.with_indifferent_access
    assert first.key?(:s)
    assert first.key?(:t)
    compact
  end

end
