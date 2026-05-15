require 'test_helper'

class StatementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @statement = statements(:one)
  end

  test "should get index" do
    get statements_url
    assert_response :success
  end

  test "statements index renders harmonized table shell and filters" do
    get statements_url

    assert_response :success
    assert_select ".harmonized-table-shell", 1
    assert_select ".harmonized-table-filters", 1
    assert_select 'form[action="/statements"][method="get"]', 1
    assert_select 'input[type="submit"][value="Apply filters"]', 1
    assert_select 'a', text: "Reset filters"
  end

  test "statements index renders sortable headers" do
    get statements_url

    assert_response :success
    assert_select 'th a[href*="sort=id"]'
    assert_select 'th a[href*="sort=cache"]'
    assert_select 'th a[href*="sort=status"]'
    assert_select 'th a[href*="sort=updated_at"]'
  end

  test "statements index preserves active filters in sort links" do
    get statements_url, params: { cache: "MyString", status: "initial", manual: "false", per_page: "10" }

    assert_response :success
    assert_sort_link_preserves_filters(
      label: "Cache",
      sort_key: "cache",
      params: {
        cache: "MyString",
        status: "initial",
        manual: "false",
        per_page: "10"
      }
    )
  end

  test "statements index falls back safely for invalid sort and direction" do
    get statements_url, params: { sort: "bogus", direction: "sideways" }

    assert_response :redirect
    assert_redirected_to statements_url
  end

  test "statements index renders empty state" do
    get statements_url, params: { cache: "no-such-statement-cache-value" }

    follow_redirect! if response.redirect?
    assert_response :success
    assert_select ".harmonized-table-empty-state", 1
  end

  test "statements index does not fetch" do
    assert_read_only_page_does_not_fetch

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
    assert_read_only_page_does_not_fetch
    get statement_url(@statement)
    assert_response :success
  end

  test "statement show renders harmonized card hooks and preserves operator context" do
    assert_read_only_page_does_not_fetch

    get statement_url(@statement)

    assert_response :success
    assert_select ".harmonized-card-grid", minimum: 1
    assert_select ".harmonized-card", minimum: 1
    assert_select ".harmonized-card-title", minimum: 1
    assert_select ".harmonized-card-value", minimum: 1
    assert_select ".harmonized-card-actions", minimum: 1
    assert_select 'details[data-operator-context-card]'
  end

  test "statement pages render cache links without fetching" do
    assert_read_only_page_does_not_fetch
    website = Website.create!(
      name: "statement rollout active",
      seedurl: "statement-rollout-active",
      graph_name: "http://example.com/statement-rollout-active",
      default_language: "en",
      distillator_mode: "active"
    )
    webpage = Webpage.create!(
      url: "http://example.com/statement-rollout-active",
      language: "en",
      rdf_uri: "rdf:statement-rollout-active",
      rdfs_class: rdfs_classes(:one),
      website: website
    )
    source = Source.create!(
      algorithm_value: "xpath=//title/text()",
      selected: true,
      selected_by: "Distillator",
      language: "en",
      render_js: false,
      property: properties(:one),
      website: website
    )
    statement = Statement.create!(
      cache: "Active rollout cache",
      source: source,
      webpage: webpage,
      status: "ok",
      status_origin: "condenser_refresh"
    )

    get statement_url(statement)
    assert_response :success
    assert_select 'details[data-operator-context-card]'
    assert_select 'details[data-context-domain="status"]'
    assert_select 'details[data-context-domain="actions"]'
    assert_select 'details[data-context-domain="details"]'
    assert_includes @response.body, "Condenser active"
    assert_includes @response.body, "Condenser serves fetch/cache results; legacy Wringer remains available for inspection."
    assert_includes @response.body, "Open active cache"
    assert_includes @response.body, "Active: Condenser"
    assert_includes @response.body, "Inspect legacy Wringer"
    assert_operator @response.body.scan("Inspect legacy Wringer").size, :>=, 2
    assert_includes @response.body, "Diagnose refresh"

    get webpage_statements_url(url: webpage.url)
    assert_response :success
    assert_includes @response.body, "Condenser active"
    assert_includes @response.body, "Open active cache"
    assert_includes @response.body, "Active: Condenser"
  end

  test "trace-step active cache link follows shadow mode" do
    previous_mode = ENV["DISTILLATOR_FETCH_MODE"]
    helper_proxy = mock("helper_proxy")
    @statement.webpage.website.update!(distillator_mode: "shadow")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: ["value"],
      trace: [
        {
          step: 1,
          type: "url",
          code: "url='http://example.org/page'",
          input: [],
          output: [],
          url_before: "http://example.org/page",
          url_after: "http://example.org/page",
          website_id: @statement.webpage.website_id,
          wringer: { signals: { network_status: "ok" } }
        }
      ],
      errors: []
    )
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    ENV["DISTILLATOR_FETCH_MODE"] = "shadow"
    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    follow_redirect_with_trace_visibility("always", "3")

    assert_response :success
    assert_includes @response.body, "/condenser/cache/compare?uri="
    assert_includes @response.body, "Compare Condenser vs Wringer"
    assert_includes @response.body, "Active: Wringer + Shadow comparison"
  ensure
    ENV["DISTILLATOR_FETCH_MODE"] = previous_mode
  end

  test "legacy statement page shows legacy warning" do
    assert_read_only_page_does_not_fetch
    @statement.webpage.website.update!(distillator_mode: "legacy")

    get statement_url(@statement)

    assert_response :success
    assert_includes @response.body, "Legacy Wringer active"
    assert_includes @response.body, "Wringer remains the production fetch path."
    assert_includes @response.body, "Active: Wringer"
  end

  test "show does not execute trace rendering even when dsl_trace cookie is set" do
    assert_read_only_page_does_not_fetch
    get statement_url(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_response :success
    assert_no_match(/Algorithm Trace/, response.body)
  end

  test "trace persists across refresh" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")
    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    assert session[:dsl_trace].present?
    cookies[:trace_visibility] = "always"
    cookies[:trace_view_mode] = "3"

    get statement_url(@statement)
    assert_response :success
    assert assigns(:trace).present?
    assert session[:dsl_trace].present?

    get statement_url(@statement)
    assert_response :success
    assert assigns(:trace).present?
    assert session[:dsl_trace].present?
  end

  test "trace is not mutated between requests" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")
    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    original = Marshal.load(Marshal.dump(session[:dsl_trace]))
    cookies[:trace_visibility] = "always"
    cookies[:trace_view_mode] = "3"

    get statement_url(@statement)
    trace_for_view = assigns(:trace)
    steps = trace_for_view[:steps] || trace_for_view["steps"] || []
    steps << { "step" => "mutated" }
    assert_equal original.deep_stringify_keys, session[:dsl_trace].deep_stringify_keys
  end

  test "nested trace structures are not mutated" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: ["value"],
      trace: [
        {
          step: 1,
          type: "url",
          code: "url='http://example.com'",
          input: [],
          output: [],
          probe: { result: { status: "ok", xpath: "//title", output: ["value"] } },
          wringer: { signals: { network_status: "ok" } }
        }
      ],
      errors: []
    )
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    original = Marshal.load(Marshal.dump(session[:dsl_trace]))
    cookies[:trace_visibility] = "always"
    cookies[:trace_view_mode] = "3"
    get statement_url(@statement)

    trace = assigns(:trace)
    mutate_nested = lambda do |obj|
      case obj
      when Hash
        obj.each do |k, v|
          if v.is_a?(Hash) || v.is_a?(Array)
            return true if mutate_nested.call(v)
          elsif v.is_a?(String)
            obj[k] = "changed"
            return true
          end
        end
      when Array
        obj.each_with_index do |v, i|
          if v.is_a?(Hash) || v.is_a?(Array)
            return true if mutate_nested.call(v)
          elsif v.is_a?(String)
            obj[i] = "changed"
            return true
          end
        end
      end
      false
    end

    mutated = mutate_nested.call(trace)

    assert mutated, "Expected to find mutable nested trace signals in assigns(:trace)"
    assert_equal original.deep_stringify_keys, session[:dsl_trace].deep_stringify_keys
  end

  test "trace defaults to empty array when not present" do
    get statement_url(@statement)
    session[:dsl_trace] = nil

    get statement_url(@statement)

    assert_equal [], assigns(:trace)
  end

  test "refresh + show uses real DSL pipeline" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }

    follow_redirect_with_trace_visibility("always", "3")

    assert_response :success
    assert_match(/Algorithm Trace/, response.body)
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

  test "refresh_webpage keeps html notice compact for nested distillator abort payloads" do
    nested_errors = [
      {
        "Property id 123" => [
          {
            error_type: "phantomjs_unavailable",
            error: "Legacy PhantomJS renderer is unavailable",
            signals: {
              blocking_issue_key: "phantomjs_unavailable",
              renderer_fallback: "direct_url",
              primary_issue_category: "renderer",
              phantomjs_iframe_extraction: false
            }
          }
        ]
      },
      {
        "Property id 456" => [
          {
            error_type: "redirect_to_listing",
            error: "Fetch content blocked by redirect_to_listing",
            signals: {
              blocking_issue_key: "redirect_to_listing",
              renderer_fallback: "direct_url"
            }
          }
        ]
      },
      {
        "Property id 789" => [
          {
            error_type: "timeout",
            error: "execution expired",
            signals: { blocking_issue_key: "timeout" }
          }
        ]
      }
    ]

    StatementsController.any_instance.expects(:refresh_webpage_statements).returns(nested_errors)

    assert_nothing_raised do
      patch refresh_webpage_statements_path(url: webpages(:six).url)
    end

    assert_redirected_to webpage_statements_path(url: webpages(:six).url)
    assert_match(/Refresh completed with 3 errors\./, flash[:notice].to_s)
    assert_match(/phantomjs_unavailable/, flash[:notice].to_s)
    assert_no_match(/renderer_fallback/, flash[:notice].to_s)
    assert_no_match(/primary_issue_category/, flash[:notice].to_s)
    assert_operator Marshal.dump(session.to_hash).bytesize, :<, 3000
  end

  test "refresh_webpage returns explicit missing webpage errors" do
    patch refresh_webpage_statements_path(format: :json), params: { url: "https://example.org/missing" }

    assert_response :not_found
    payload = JSON.parse(response.body)
    assert_equal "Webpage not found for URL: https://example.org/missing", payload["error"]
    assert_equal "https://example.org/missing", payload["url"]

    patch refresh_webpage_statements_path(url: "https://example.org/missing")

    assert_redirected_to webpage_statements_path(url: "https://example.org/missing")
    follow_redirect!
    assert_match(/Webpage not found for URL: https:\/\/example.org\/missing/, response.body)
  end

  test "refresh_rdf_uri forwards force_scrape_every_hrs 1 and reports per-webpage errors in json" do
    rdf_uri = webpages(:one).rdf_uri
    expected_options = { force_scrape_every_hrs: "1" }
    expected_error = [{ "Property id 123" => { cache: ["failed refresh"] } }]

    StatementsController.any_instance.expects(:refresh_webpage_statements).with do |webpage, default_language, scrape_options|
      assert_equal rdf_uri, webpage.rdf_uri
      assert_equal webpage.website.default_language, default_language
      assert_equal expected_options, scrape_options
      true
    end.at_least_once.returns(expected_error)

    patch refresh_rdf_uri_statements_path(format: :json), params: {
      rdf_uri: rdf_uri,
      force_scrape_every_hrs: "1"
    }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_includes payload["message"], "Webpage id:"
    assert_includes payload["message"], "failed refresh"
  end

  test "refresh_rdf_uri keeps html notice compact for nested distillator abort payloads" do
    rdf_uri = webpages(:one).rdf_uri
    nested_errors = [
      {
        "Property id 123" => [
          {
            error_type: "phantomjs_unavailable",
            error: "Legacy PhantomJS renderer is unavailable",
            signals: {
              blocking_issue_key: "phantomjs_unavailable",
              renderer_fallback: "direct_url",
              primary_issue_category: "renderer"
            }
          }
        ]
      }
    ]

    StatementsController.any_instance.expects(:refresh_webpage_statements).at_least_once.returns(nested_errors)

    assert_nothing_raised do
      patch refresh_rdf_uri_statements_path, params: { rdf_uri: rdf_uri }
    end

    assert_redirected_to statements_path(rdf_uri: rdf_uri)
    assert_match(/URI refreshed with \d+ webpage errors\./, flash[:notice].to_s)
    assert_match(/phantomjs_unavailable/, flash[:notice].to_s)
    assert_no_match(/renderer_fallback/, flash[:notice].to_s)
    assert_no_match(/primary_issue_category/, flash[:notice].to_s)
    assert_operator Marshal.dump(session.to_hash).bytesize, :<, 3000
  end

  test "refresh_rdf_uri forwards force_scrape_every_hrs 0 to statement refresh service" do
    rdf_uri = webpages(:one).rdf_uri

    StatementsController.any_instance.expects(:refresh_webpage_statements).with do |_webpage, _default_language, scrape_options|
      assert_equal({ force_scrape_every_hrs: "0" }, scrape_options)
      true
    end.at_least_once.returns([])

    patch refresh_rdf_uri_statements_path(format: :json), params: {
      rdf_uri: rdf_uri,
      force_scrape_every_hrs: "0"
    }

    assert_response :success
    payload = JSON.parse(response.body)
    assert_includes payload["message"], "URI refreshed."
  end

  test "refresh_rdf_uri returns explicit missing rdf_uri errors" do
    patch refresh_rdf_uri_statements_path(format: :json), params: { rdf_uri: "footlight:missing" }

    assert_response :not_found
    payload = JSON.parse(response.body)
    assert_equal "No webpages found for RDF URI: footlight:missing", payload["error"]
    assert_equal "footlight:missing", payload["rdf_uri"]

    patch refresh_rdf_uri_statements_path(rdf_uri: "footlight:missing")

    assert_redirected_to statements_path(rdf_uri: "footlight:missing")
    follow_redirect!
    assert_match(/No webpages found for RDF URI: footlight:missing/, response.body)
  end

  test "refresh_statement populates distillator fetch cache through the real dsl fetch seam" do
    previous_mode = ENV["DISTILLATOR_FETCH_MODE"]
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    Distillator::FetchCache.delete_all
    website = Website.create!(
      name: "Controller Refresh Fixture",
      seedurl: "controller-refresh-fixture",
      graph_name: "https://fixtures.example/controller-refresh",
      default_language: "en",
      distillator_mode: "active"
    )
    rdfs_class = RdfsClass.create!(name: "ControllerRefreshClass")
    property = Property.create!(
      label: "Controller Refresh Title",
      value_datatype: "MyString",
      uri: "http://schema.org/name",
      rdfs_class: rdfs_class
    )
    webpage = Webpage.create!(
      url: "https://www.culture3r.com/evenements/gabrielle-caron-rodage/",
      language: "en",
      rdf_uri: "http://example.org/rdf/culture3r",
      rdfs_class: rdfs_class,
      website: website
    )
    source_one = Source.create!(
      algorithm_value: "xpath=//h1/text()",
      selected: true,
      selected_by: "test",
      language: "en",
      render_js: false,
      property: property,
      website: website
    )
    stat_one = Statement.create!(
      cache: "old one",
      status: "initial",
      status_origin: "test",
      cache_refreshed: 1.day.ago,
      cache_changed: 1.day.ago,
      source: source_one,
      webpage: webpage,
      selected_individual: false
    )
    html = "<html><body><h1>Gabrielle Caron</h1></body></html>"

    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::FetchGuard.stubs(:check_response).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::NativeFetch.expects(:call).once.returns(
      status: :ok,
      body: html,
      raw_body: html,
      headers: { content_type: "text/html" },
      final_url: webpage.url,
      redirect_chain: [webpage.url],
      wringer: { signals: {}, hints: [] },
      http_code: 200
    )

    patch refresh_statement_path(stat_one)

    assert_redirected_to statement_url(stat_one)
    cache = Distillator::FetchCache.find_by(normalized_url: webpage.url)
    assert cache
    assert_equal webpage.url, cache.normalized_url
    assert_equal 200, cache.http_response_code
    assert_equal html, cache.html
    assert_equal html, cache.body
    assert_equal({ "content_type" => "text/html" }, cache.headers)
    assert_equal [webpage.url], cache.redirect_chain
    assert cache.signals.present?
    assert cache.hints.is_a?(Array)
    assert cache.scrape_date.present?
    assert cache.successful_refresh.present?
    assert_equal "Gabrielle Caron", stat_one.reload.cache

    get "/distillator/cache.json", params: { term: "culture3r" }
    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal [cache.id], payload.map { |row| row["id"] }
  ensure
    ENV["DISTILLATOR_FETCH_MODE"] = previous_mode
  end

  test "refresh helper proxy does not leak trace cookies across requests" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }

    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    patch refresh_statement_path(@statement)

    assert_redirected_to statement_url(@statement)
    assert_nil session[:dsl_trace]
  end

  test "refresh json success returns structured ok payload without redirect" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: ["value"],
      trace: nil,
      errors: []
    )
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement, format: :json)

    assert_response :success
    assert_not response.redirect?
    body = JSON.parse(response.body).with_indifferent_access
    assert_equal "ok", body[:status]
    assert_equal @statement.id, body[:statement_id]
    assert_equal true, body[:result_present]
    assert_equal false, body[:trace_present]
  end

  test "refresh json abort returns structured error payload with 422 and no redirect" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: ["abort_update", { error: "Invalid URL resolved from nil", error_type: "InvalidURL", step: "url", source: "dsl_runner" }],
      trace: nil,
      errors: ["Scrape aborted (InvalidURL): Invalid URL resolved from nil"]
    )
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement, format: :json)

    assert_response :unprocessable_entity
    assert_not response.redirect?
    body = JSON.parse(response.body).with_indifferent_access
    assert_equal "error", body[:status]
    assert_equal "dsl_abort", body[:kind]
    assert_equal "Invalid URL resolved from nil", body[:error]
    assert_equal "InvalidURL", body[:error_type]
    assert_equal "url", body[:step]
    assert_equal "dsl_runner", body[:source]
  end

  test "refresh json non-abort error returns refresh_error kind with 422 and no redirect" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: nil,
      trace: nil,
      errors: ["DSL returned blank result (possible parsing failure)"]
    )
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement, format: :json)

    assert_response :unprocessable_entity
    assert_not response.redirect?
    body = JSON.parse(response.body).with_indifferent_access
    assert_equal "error", body[:status]
    assert_equal "refresh_error", body[:kind]
    assert_equal "DSL returned blank result (possible parsing failure)", body[:error]
    assert_equal "RefreshError", body[:error_type]
    assert_nil body[:step]
    assert_equal "statements_controller", body[:source]
  end

  test "refresh json malformed abort payload is explicit invalid abort payload error" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: ["abort_update", "invalid_payload"],
      trace: nil,
      errors: ["Scrape aborted"]
    )
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement, format: :json)

    assert_response :unprocessable_entity
    assert_not response.redirect?
    body = JSON.parse(response.body).with_indifferent_access
    assert_equal "error", body[:status]
    assert_equal "dsl_abort", body[:kind]
    assert_equal "InvalidAbortPayload", body[:error_type]
    assert_equal "Malformed abort payload", body[:error]
    assert_equal "statements_controller", body[:source]
  end

  test "refresh html success redirects with notice" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: ["value"],
      trace: nil,
      errors: []
    )
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement)

    assert_redirected_to statement_url(@statement)
    assert_equal "Statement was successfully refreshed.", flash[:notice]
    assert_nil flash[:alert]
  end

  test "refresh html abort redirects with alert and without success notice" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: ["abort_update", { error: "Invalid URL resolved from nil", error_type: "InvalidURL", step: "url", source: "dsl_runner" }],
      trace: nil,
      errors: ["Scrape aborted (InvalidURL): Invalid URL resolved from nil"]
    )
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement)

    assert_redirected_to statement_url(@statement)
    assert_match(/Statement Error:/, flash[:alert].to_s)
    assert_match(/InvalidURL/, flash[:alert].to_s)
    assert_nil flash[:notice]
  end

  test "refresh html abort keeps flash compact and session under threshold" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: ["abort_update", {
        error: "Legacy PhantomJS renderer is unavailable",
        error_type: "phantomjs_unavailable",
        step: "url",
        signals: {
          blocking_issue_key: "phantomjs_unavailable",
          renderer_fallback: "direct_url",
          primary_issue_category: "renderer",
          phantomjs_iframe_extraction: false
        },
        hints: ["legacy_phantomjs", "phantomjs_unavailable"]
      }],
      trace: build_large_realistic_trace(20),
      errors: ["Scrape aborted (phantomjs_unavailable): issue=phantomjs_unavailable: Legacy PhantomJS renderer is unavailable"]
    )
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    assert_nothing_raised do
      patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    end

    assert_redirected_to statement_url(@statement)
    assert_match(/phantomjs_unavailable/, flash[:alert].to_s)
    assert_no_match(/renderer_fallback/, flash[:alert].to_s)
    assert_no_match(/primary_issue_category/, flash[:alert].to_s)
    assert_no_match(/phantomjs_iframe_extraction/, flash[:alert].to_s)
    assert_operator Marshal.dump(session.to_hash).bytesize, :<, 3000
  end

  test "success with trace shows notice and trace on redirected show page" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect_with_trace_visibility
    assert_response :success
    assert_match(/Statement was successfully refreshed\./, response.body)
    assert_no_match(/Statement Error:/, response.body)
    assert_match(/Algorithm Trace/, response.body)
    assert_match(/Step 1/, response.body)
    assert_match(/Step 1 — manual/, response.body)
    assert_match(/Traceable value/, response.body)
    assert_not_nil session[:dsl_trace]
  end

  test "no error + auto trace visibility hides trace" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=auto" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect_with_trace_visibility("auto")
    assert_response :success
    assert_no_match(/Algorithm Trace/, response.body)
    assert_not_nil session[:dsl_trace]
  end

  test "error + auto trace visibility shows trace" do
    @statement.source.update!(algorithm_value: "ruby=$array.each {|a| a")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=auto" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect_with_trace_visibility("auto")
    assert_response :success
    assert_match(/Algorithm Trace/, response.body)
    assert_not_nil session[:dsl_trace]
  end

  test "trace view labels wringer fetch failures as fetch error" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: nil,
      trace: [
        {
          step: 1,
          type: "url",
          code: "url='http://example.com'",
          input: [],
          output: [],
          error: { error: "network down", error_type: "WringerFetchError", source: "wringer" },
          wringer: { error_type: "WringerFetchError", source: "wringer", signals: {}, hints: [] }
        }
      ],
      errors: ["network down"]
    )
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect_with_trace_visibility("always", "3")
    assert_response :success
    assert_match(/Fetch error/, response.body)
  end

  test "trace view labels dsl extraction failures as extraction error" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: nil,
      trace: [
        {
          step: 1,
          type: "xpath",
          code: "xpath=//h1/text()",
          input: [],
          output: [],
          error: { error: "No nodes matched", error_type: "ExtractionFailed", source: "dsl_runner" },
          wringer: { signals: {}, hints: [] }
        }
      ],
      errors: ["No nodes matched"]
    )
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect_with_trace_visibility("always", "3")
    assert_response :success
    assert_match(/Extraction error/, response.body)
  end

  test "always trace visibility always shows trace" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect_with_trace_visibility
    assert_response :success
    assert_match(/Algorithm Trace/, response.body)
    assert_not_nil session[:dsl_trace]
  end

  test "hidden trace visibility never shows trace" do
    @statement.source.update!(algorithm_value: "ruby=$array.each {|a| a")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=hidden" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect_with_trace_visibility("hidden")
    assert_response :success
    assert_no_match(/Algorithm Trace/, response.body)
    assert_not_nil session[:dsl_trace]
  end

  test "defaults trace_view_mode to trace rendering when cookie is missing" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect_with_trace_visibility("always")
    assert_response :success
    assert_match(/Algorithm Trace/, response.body)
    assert_not_nil session[:dsl_trace]
  end

  test "uses cookie trace_view_mode to hide trace when mode is 2" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect_with_trace_visibility("always", "2")
    assert_response :success
    assert_no_match(/Algorithm Trace/, response.body)
    assert_not_nil session[:dsl_trace]
  end

  test "success without trace shows notice and does not render trace on redirected show page" do
    @statement.source.update!(algorithm_value: "manual=No Trace")

    patch refresh_statement_path(@statement)
    assert_redirected_to statement_url(@statement)
    assert_nil session[:dsl_trace]

    follow_redirect_with_trace_visibility
    assert_response :success
    assert_match(/Statement was successfully refreshed\./, response.body)
    assert_no_match(/Statement Error:/, response.body)
    assert_no_match(/Algorithm Trace/, response.body)
    assert_nil session[:dsl_trace]
  end

  test "error with trace shows alert and keeps trace rendering" do
    @statement.source.update!(algorithm_value: "ruby=$array.each {|a| a")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect_with_trace_visibility
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
    assert_not_nil session[:dsl_trace]
  end

  test "error without trace shows alert and no trace rendering" do
    @statement.source.update!(algorithm_value: "ruby=$array.each {|a| a")

    patch refresh_statement_path(@statement)
    assert_redirected_to statement_url(@statement)
    assert_nil session[:dsl_trace]

    follow_redirect_with_trace_visibility
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
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement)
    assert_redirected_to statement_url(@statement)
    assert_nil session[:dsl_trace]

    follow_redirect_with_trace_visibility
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
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect_with_trace_visibility
    assert_response :success
    assert_match(/Statement Error: boom/, response.body)
    assert_no_match(/Statement was successfully refreshed\./, response.body)
    assert_error_alert_if_present
    assert_match(/Algorithm Trace/, response.body)
    body = response.body
    assert body.index("Statement Error") < body.index("Algorithm Trace")
    assert_not_nil session[:dsl_trace]
  end

  test "error is not swallowed when trace is present" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: nil,
      trace: [{ step: 1, type: "ruby", input: ["in"], output: ["out"] }],
      errors: ["critical failure"]
    )
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect_with_trace_visibility
    assert_response :success
    assert_match(/Statement Error: critical failure/, response.body)
    assert_no_match(/Statement was successfully refreshed\./, response.body)
    assert_error_alert_if_present
    assert_match(/Algorithm Trace/, response.body)
    body = response.body
    assert body.index("Statement Error") < body.index("Algorithm Trace")
    assert_not_nil session[:dsl_trace]
  end

  test "empty trace still shows error" do
    helper_proxy = mock("helper_proxy")
    helper_proxy.expects(:refresh_statement_helper).with(@statement).returns(
      data: nil,
      trace: [],
      errors: ["failure"]
    )
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    trace = session[:dsl_trace].with_indifferent_access
    assert_equal 2, trace[:version]
    assert_empty trace[:steps]

    follow_redirect_with_trace_visibility
    assert_response :success
    assert_match(/Statement Error: failure/, response.body)
    assert_no_match(/Statement was successfully refreshed\./, response.body)
    assert_error_alert_if_present
    assert_match(/Algorithm Trace/, response.body)
    body = response.body
    assert body.index("Statement Error") < body.index("Algorithm Trace")
    assert_not_nil session[:dsl_trace]
  end

  test "refresh stores formatted trace in session" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)

    assert_nil flash[:dsl_trace]
    trace = assert_session_trace_present_and_structured

    first = trace[:steps].first.with_indifferent_access
    assert_equal 1, first[:s]
    assert_equal "manual", first[:t]

    follow_redirect_with_trace_visibility
    assert_response :success
    assert_not_nil session[:dsl_trace]
  end

  test "show retrieves trace after redirect and keeps session trace" do
    @statement.source.update!(algorithm_value: "manual=Traceable value")

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    assert_redirected_to statement_url(@statement)
    assert_session_trace_present_and_structured

    follow_redirect_with_trace_visibility
    assert_response :success
    assert_match(/Algorithm Trace/, response.body)
    assert_not_nil session[:dsl_trace]
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
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    patch refresh_statement_path(@statement)
    assert_redirected_to statement_url(@statement)
    assert_nil session[:dsl_trace]

    follow_redirect_with_trace_visibility
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

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    body = response.body

    assert_match(/Algorithm Trace/, body)
    assert_match(/NoMethodError/, body)
  end

  test "all trace steps are preserved in session and rendered" do
    trace = (1..10).map do |i|
      { step: i, type: "ruby" }
    end

    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }

    assert_equal 10, session[:dsl_trace].with_indifferent_access[:steps].size

    follow_redirect_with_trace_visibility

    (1..10).each do |i|
      assert_match(/Step #{i}/, response.body)
    end
  end

  test "trace displays state transitions instead of table" do
    trace = [
      { step: 1, type: "ruby", input_preview: ["one"], output_preview: ["two"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

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

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    assert_match(/\[\d+ items:/, response.body)
    assert_match(%r{https://example.com}, response.body)
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

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    displayed_code = response.body[%r{<div class="trace-code">\s*<code>\s*<span[^>]*>([^<]+)</span>\s*</code>}m, 1]
    assert displayed_code.present?
    assert_operator displayed_code.length, :<=, StatementsController::TRACE_CODE_DEFAULT
    assert_match(/x{20}/, displayed_code)
    assert_no_match(/x{150}/, displayed_code)
    assert_match(/title="/, response.body)
  end

  test "code truncation honors trace_code_display_length cookie" do
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

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always; trace_code_display_length=200" }
    follow_redirect_with_trace_visibility

    displayed_code = response.body[%r{<div class="trace-code">\s*<code>\s*<span[^>]*>([^<]+)</span>\s*</code>}m, 1]
    assert displayed_code.present?
    assert_operator displayed_code.length, :<=, 200
    assert_match(/title="/, response.body)
  end

  test "xpath step is classified as extraction" do
    trace = [{ step: 1, type: "xpath", code: "//div", output_preview: [] }]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    assert_match(/extraction/, response.body)
  end

  test "ruby reject is classified as filter" do
    trace = [
      { step: 1, type: "ruby", code: "$array.map{}", output_preview: ["A"] },
      { step: 2, type: "ruby", code: "$array.reject{}", output_preview: ["B"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    assert_match(/filter \(Δ changed\)/, response.body)
  end

  test "tooltip contains full rendered code value" do
    trace = [{ step: 1, type: "ruby", code: "alpha_beta", output_preview: [] }]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

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

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    assert_match(/⚠/, response.body)
    assert_match(/NoMethodError/, response.body)
  end

  test "probe result is rendered in trace viewer" do
    trace = [
      {
        step: 1,
        type: "url",
        output_preview: []
      },
      {
        step: 2,
        type: "xpath",
        code: "//h1/text()",
        output_preview: [],
        probe: {
          xpath: "//title",
          output: ["Probe Title"]
        }
      }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    trace_payload = session[:dsl_trace].with_indifferent_access
    second = trace_payload[:steps].second.with_indifferent_access
    assert_equal "//title", second.dig(:p, :x)
    assert_match(/Probe Title/, second.dig(:p, :o).to_s)

    follow_redirect_with_trace_visibility

    assert_match(%r{Probe //title}, response.body)
    assert_match(/Probe Title/, response.body)
  end

  test "delta shows added elements in array" do
    trace = [
      { step: 1, type: "ruby", output_preview: [] },
      { step: 2, type: "ruby", output_preview: ["A"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    assert_match(/Δ added/, response.body)
    assert_no_match(/class="trace-delta"/, response.body)
  end

  test "delta shows removed elements in array" do
    trace = [
      { step: 1, type: "ruby", output_preview: %w[A B] },
      { step: 2, type: "ruby", output_preview: ["A"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

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

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    assert_match(/Δ changed/, response.body)
    assert_match(%r{\+https://example.com}, response.body)
  end

  test "no delta shown when state unchanged" do
    trace = [
      { step: 1, type: "ruby", output_preview: ["A"] },
      { step: 2, type: "ruby", output_preview: ["A"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    assert_match(/No change/, response.body)
    assert_no_match(/class="trace-delta"/, response.body)
  end

  test "no change is rendered when consecutive outputs are identical" do
    trace = [
      { step: 1, type: "ruby", output_preview: ["A"] },
      { step: 2, type: "ruby", output_preview: ["A"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    assert_match(/No change/, response.body)
  end

  test "no result is rendered when output stays empty" do
    trace = [
      { step: 1, type: "ruby", output_preview: [] },
      { step: 2, type: "ruby", output_preview: [] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    assert_match(/No result/, response.body)
  end

  test "exactly one semantic label is rendered per step" do
    trace = [
      { step: 1, type: "ruby", output_preview: [] },
      { step: 2, type: "ruby", output_preview: ["A"] },
      { step: 3, type: "ruby", output_preview: ["B"] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    assert_equal 3, response.body.scan(/class="trace-semantic"/).size
  end

  test "output is always shown even when empty array" do
    trace = [
      { step: 1, type: "ruby", output_preview: [] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    assert_match(/→\s*\[\]/, response.body)
  end

  test "input is not shown when output is empty array" do
    trace = [
      { step: 1, type: "ruby", input_preview: ["INPUT_ONLY_MARKER"], output_preview: [] }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    assert_match(/→\s*\[\]/, response.body)
    assert_no_match(/→\s*INPUT_ONLY_MARKER/, response.body)
  end

  test "compact trace urls are reconstructed correctly in view" do
    trace = [
      { step: 1, type: "ruby", url_before: "http://example.com/a", url_after: "http://example.com/b" },
      { step: 2, type: "ruby", url_before: "http://example.com/a", url_after: "http://example.com/b" }
    ]
    stub_helper_with_trace(trace)

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    compact = session[:dsl_trace].with_indifferent_access
    assert_equal "http://example.com/a", compact[:initial].with_indifferent_access[:url]
    assert_equal ["http://example.com/b"], compact[:urls]

    follow_redirect_with_trace_visibility
    assert_match(%r{http://example.com/b}, response.body)
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

  test "expand_trace_for_view reconstructs v2 probe payload" do
    compact = {
      version: 2,
      initial: { state: nil, url: "http://example.com/start" },
      urls: [],
      steps: [
        { s: 1, t: "url", o: "[]" },
        { s: 2, t: "xpath", o: "[]", p: { st: "ok", x: "//title", o: ["Probe Title"] } }
      ]
    }

    expanded = StatementsController.new.expand_trace_for_view(compact)
    probe = expanded.second[:probe].with_indifferent_access

    assert_equal true, probe[:ok]
    assert_equal "ok", probe[:result][:status]
    assert_equal "//title", probe[:result][:xpath]
    assert_equal ["Probe Title"], probe[:result][:output]
  end

  test "trace storage does not trigger CookieOverflow" do
    large_trace = build_large_realistic_trace(20)
    stub_helper_with_trace(large_trace)

    assert_nothing_raised do
      patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
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

    patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
    follow_redirect_with_trace_visibility

    assert_match(/Statement Error:/, response.body)
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
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)

    assert_nothing_raised do
      patch refresh_statement_path(@statement), headers: { "Cookie" => "dsl_trace=true; trace_visibility=always" }
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

    follow_redirect_with_trace_visibility
    assert_response :success
    assert_not_nil session[:dsl_trace]
  end

  test "batch update with many abort payloads keeps flash compact and avoids cookie overflow" do
    statements = Array.new(6, @statement)
    helper_proxy = mock("helpers_proxy")
    6.times do
      helper_proxy.expects(:refresh_statement_helper).returns(
        data: ["abort_update", {
          error: "Legacy PhantomJS renderer is unavailable",
          error_type: "phantomjs_unavailable",
          step: "url",
          signals: {
            blocking_issue_key: "phantomjs_unavailable",
            renderer_fallback: "direct_url",
            primary_issue_category: "renderer",
            phantomjs_iframe_extraction: false
          },
          hints: ["legacy_phantomjs", "phantomjs_unavailable"]
        }],
        trace: nil,
        errors: ["Scrape aborted (phantomjs_unavailable): issue=phantomjs_unavailable: Legacy PhantomJS renderer is unavailable"]
      )
    end
    StatementsController.any_instance.stubs(:build_query).returns(statements)
    StatementsController.any_instance.stubs(:helpers).returns(helper_proxy)

    assert_nothing_raised do
      post batch_update_statements_path, params: { commit: "Refresh all listed" }
    end

    assert_redirected_to statements_path
    assert_match(/Refresh completed with 6 errors\./, flash[:notice].to_s)
    assert_match(/phantomjs_unavailable/, flash[:notice].to_s)
    assert_no_match(/renderer_fallback/, flash[:notice].to_s)
    assert_no_match(/primary_issue_category/, flash[:notice].to_s)
    assert_no_match(/phantomjs_iframe_extraction/, flash[:notice].to_s)
    assert_operator Marshal.dump(session.to_hash).bytesize, :<, 3000
  end

  test "batch form preserves full statements filter and pagination context" do
    get statements_url, params: {
      rdf_uri: "uri1",
      seedurl: "one",
      prop: properties(:one).id.to_s,
      source: sources(:one).id.to_s,
      cache: "MyString",
      status: "initial",
      manual: "false",
      selected: "true",
      selected_individual: "false",
      sort: "cache",
      direction: "desc",
      page: "2",
      per_page: "10"
    }

    assert_response :success
    assert_select 'form[action="/statements/batch_update"] input[type="hidden"][name="rdf_uri"][value="uri1"]', 1
    assert_select 'form[action="/statements/batch_update"] input[type="hidden"][name="seedurl"][value="one"]', 1
    assert_select "form[action=\"/statements/batch_update\"] input[type=\"hidden\"][name=\"prop\"][value=\"#{properties(:one).id}\"]", 1
    assert_select "form[action=\"/statements/batch_update\"] input[type=\"hidden\"][name=\"source\"][value=\"#{sources(:one).id}\"]", 1
    assert_select 'form[action="/statements/batch_update"] input[type="hidden"][name="cache"][value="MyString"]', 1
    assert_select 'form[action="/statements/batch_update"] input[type="hidden"][name="status"][value="initial"]', 1
    assert_select 'form[action="/statements/batch_update"] input[type="hidden"][name="manual"][value="false"]', 1
    assert_select 'form[action="/statements/batch_update"] input[type="hidden"][name="selected"][value="true"]', 1
    assert_select 'form[action="/statements/batch_update"] input[type="hidden"][name="selected_individual"][value="false"]', 1
    assert_select 'form[action="/statements/batch_update"] input[type="hidden"][name="sort"][value="cache"]', 1
    assert_select 'form[action="/statements/batch_update"] input[type="hidden"][name="direction"][value="desc"]', 1
    assert_select 'form[action="/statements/batch_update"] input[type="hidden"][name="page"][value="2"]', 1
    assert_select 'form[action="/statements/batch_update"] input[type="hidden"][name="per_page"][value="10"]', 1
  end

  test "batch update only applies to the current filtered listed scope and preserves redirect context" do
    matching_one, matching_two, other_page, other_filter = create_batch_scope_statements
    StatementsController.any_instance.stubs(:build_query).returns([matching_one, matching_two])

    post batch_update_statements_path, params: {
      seedurl: matching_one.webpage.website.seedurl,
      source: matching_one.source_id.to_s,
      status: "initial",
      manual: "false",
      selected: "true",
      selected_individual: "false",
      sort: "id",
      direction: "asc",
      page: "1",
      per_page: "2",
      update_data: "{ manual: true, cache: 'batch-scope-updated' }",
      commit: "Update"
    }

    assert_redirected_to statements_path(
      seedurl: matching_one.webpage.website.seedurl,
      source: matching_one.source_id.to_s,
      status: "initial",
      manual: "false",
      selected: "true",
      selected_individual: "false",
      sort: "id",
      direction: "asc",
      page: "1",
      per_page: "2"
    )
    assert_equal true, matching_one.reload.manual
    assert_equal true, matching_two.reload.manual
    assert_equal "batch-scope-updated", matching_one.reload.cache
    assert_equal "batch-scope-updated", matching_two.reload.cache
    assert_equal false, other_page.reload.manual
    assert_equal false, other_filter.reload.manual
  end

  test "refresh all listed only applies to the current filtered listed scope and preserves redirect context" do
    matching_one, matching_two, = create_batch_scope_statements
    StatementsController.any_instance.stubs(:build_query).returns([matching_one, matching_two])
    helper_proxy = mock("batch_refresh_helpers")
    helper_proxy.expects(:refresh_statement_helper).with(matching_one).returns(data: ["ok"], trace: nil, errors: [])
    helper_proxy.expects(:refresh_statement_helper).with(matching_two).returns(data: ["ok"], trace: nil, errors: [])
    StatementsController.any_instance.stubs(:helpers).returns(helper_proxy)

    post batch_update_statements_path, params: {
      seedurl: matching_one.webpage.website.seedurl,
      source: matching_one.source_id.to_s,
      status: "initial",
      manual: "false",
      selected: "true",
      selected_individual: "false",
      sort: "id",
      direction: "asc",
      page: "1",
      per_page: "2",
      commit: "Refresh all listed"
    }

    assert_redirected_to statements_path(
      seedurl: matching_one.webpage.website.seedurl,
      source: matching_one.source_id.to_s,
      status: "initial",
      manual: "false",
      selected: "true",
      selected_individual: "false",
      sort: "id",
      direction: "asc",
      page: "1",
      per_page: "2"
    )
  end

  test "review all listed only applies to the current filtered listed scope and preserves redirect context" do
    matching_one, matching_two, other_page, other_filter = create_batch_scope_statements
    StatementsController.any_instance.stubs(:build_query).returns([matching_one, matching_two])
    matching_one.update!(status: "updated", status_origin: "before")
    matching_two.update!(status: "updated", status_origin: "before")
    other_page.update!(status: "updated", status_origin: "before")
    other_filter.update!(status: "updated", status_origin: "before")

    post batch_update_statements_path, params: {
      seedurl: matching_one.webpage.website.seedurl,
      source: matching_one.source_id.to_s,
      status: "updated",
      manual: "false",
      selected: "true",
      selected_individual: "false",
      sort: "id",
      direction: "asc",
      page: "1",
      per_page: "2",
      commit: "Review all listed"
    }

    assert_redirected_to statements_path(
      seedurl: matching_one.webpage.website.seedurl,
      source: matching_one.source_id.to_s,
      status: "updated",
      manual: "false",
      selected: "true",
      selected_individual: "false",
      sort: "id",
      direction: "asc",
      page: "1",
      per_page: "2"
    )
    assert_equal "ok", matching_one.reload.status
    assert_equal "ok", matching_two.reload.status
    assert_equal "condenser-admin-review-all", matching_one.reload.status_origin
    assert_equal "condenser-admin-review-all", matching_two.reload.status_origin
    assert_equal "updated", other_page.reload.status
    assert_equal "updated", other_filter.reload.status
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

  test "batch update does not write redirect listing title when distillator content failed" do
    previous_mode = ENV["DISTILLATOR_FETCH_MODE"]
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    website = Website.create!(
      name: "culturelatuque-com",
      seedurl: "culturelatuque-com",
      graph_name: "https://example.org/culturelatuque-com",
      default_language: "fr",
      distillator_mode: "active"
    )
    rdfs_class = RdfsClass.create!(name: "OvationBatchUpdateClass")
    property = Property.create!(
      label: "Ovation Batch Title",
      value_datatype: "MyString",
      uri: "http://schema.org/name",
      rdfs_class: rdfs_class
    )
    ovation_url = "https://www.ovation.ca/00001Q/fr/Event/?seriesId=series&venueId=venue"
    webpage = Webpage.create!(
      url: ovation_url,
      language: "fr",
      rdf_uri: ovation_url,
      rdfs_class: rdfs_class,
      website: website
    )
    source = Source.create!(
      algorithm_value: "xpath=//title;ruby=$array.map{|e| e.gsub(/ \\|.*/,'')}",
      selected: true,
      selected_by: "test",
      language: "fr",
      render_js: true,
      property: property,
      website: website
    )
    statement = Statement.create!(
      cache: "Existing Event Title",
      status: "ok",
      status_origin: "test",
      cache_refreshed: 1.day.ago,
      cache_changed: 1.day.ago,
      source: source,
      webpage: webpage,
      selected_individual: false
    )

    Distillator::FetchService.expects(:fetch_result).returns(
      {
        status: :ok,
        body: "<html><title>Recherche par titre</title></html>",
        raw_body: "<html><title>Recherche par titre</title></html>",
        headers: { content_type: "text/html" },
        final_url: "https://www.ovation.ca/Search/Title/",
        redirect_chain: [ovation_url, "https://www.ovation.ca/Search/Title/"],
        wringer: {
          policy_action: "abort_update",
          retry: false,
          cache: false,
          signals: {
            network_status: "ok",
            content_type: "html",
            primary_issue_key: "redirect_to_listing",
            primary_issue_severity: "failed",
            blocking_issue_key: "redirect_to_listing",
            primary_issue_label: "Redirect to listing"
          },
          hints: ["redirect_to_listing"]
        },
        http_code: 200,
        duration_ms: 0,
        fetch_path: "native"
      }
    )

    post "/statements/batch_update", params: {
      seedurl: "culturelatuque-com",
      rdf_uri: ovation_url,
      commit: "Refresh all listed"
    }

    assert_redirected_to(/statements/)
    follow_redirect!

    cache = Distillator::FetchCache.find_by!(uri_key: CGI.escape(ovation_url))

    assert_equal "Existing Event Title", statement.reload.cache
    assert_not_equal "Recherche par titre", statement.reload.cache
    assert_match "Scrape aborted", response.body
    assert_match "redirect_to_listing", response.body
    assert_equal "attempt_failed", cache.health_status
    assert_equal "redirect_to_listing", cache.primary_issue_key
    assert_nil cache.html
  ensure
    ENV["DISTILLATOR_FETCH_MODE"] = previous_mode
  end



  private

  def follow_redirect_with_trace_visibility(state = "always", view_mode = nil)
    cookies[:trace_visibility] = state
    if view_mode.present?
      cookies[:trace_view_mode] = view_mode
    else
      cookies.delete(:trace_view_mode)
      cookies.delete("trace_view_mode")
    end
    follow_redirect!
  end

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
    StatementsController.any_instance.stubs(:statement_refresh_helper_proxy).returns(helper_proxy)
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

  def assert_read_only_page_does_not_fetch
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never
  end

  def create_batch_scope_statements
    suffix = Statement.maximum(:id).to_i + 1
    website = Website.create!(
      name: "batch scope website #{suffix}",
      seedurl: "batch-scope-website-#{suffix}",
      graph_name: "http://example.com/batch-scope-website-#{suffix}",
      default_language: "en"
    )
    property = Property.create!(
      label: "Batch scope property #{suffix}",
      value_datatype: "MyString",
      uri: "http://example.com/properties/batch-scope-#{suffix}",
      rdfs_class: rdfs_classes(:one)
    )
    selected_source = Source.create!(
      algorithm_value: "manual=Batch scope selected",
      selected: true,
      selected_by: "test",
      language: "en",
      render_js: false,
      property: property,
      website: website
    )
    unselected_source = Source.create!(
      algorithm_value: "manual=Batch scope unselected",
      selected: false,
      selected_by: "test",
      language: "en",
      render_js: false,
      property: property,
      website: website
    )

    webpages = 4.times.map do |index|
      Webpage.create!(
        url: "http://example.com/batch-scope/#{suffix}/#{index}",
        language: "en",
        rdf_uri: "rdf:batch-scope:#{suffix}:#{index}",
        rdfs_class: rdfs_classes(:one),
        website: website
      )
    end

    matching_one = Statement.create!(
      cache: "batch-scope-cache-1",
      status: "initial",
      status_origin: "seed",
      source: selected_source,
      webpage: webpages[0],
      manual: false,
      selected_individual: false
    )
    matching_two = Statement.create!(
      cache: "batch-scope-cache-2",
      status: "initial",
      status_origin: "seed",
      source: selected_source,
      webpage: webpages[1],
      manual: false,
      selected_individual: false
    )
    other_page = Statement.create!(
      cache: "batch-scope-cache-3",
      status: "initial",
      status_origin: "seed",
      source: selected_source,
      webpage: webpages[2],
      manual: false,
      selected_individual: false
    )
    other_filter = Statement.create!(
      cache: "batch-scope-cache-4",
      status: "initial",
      status_origin: "seed",
      source: unselected_source,
      webpage: webpages[3],
      manual: false,
      selected_individual: false
    )

    [matching_one, matching_two, other_page, other_filter]
  end

end
