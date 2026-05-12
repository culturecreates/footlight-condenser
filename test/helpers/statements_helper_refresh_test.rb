require 'test_helper'

# StatementsHelper tests for search_cckg() only
class StatementsHelperRefreshTest < ActionView::TestCase
  tests StatementsHelper

  class CapturingLogger
    attr_reader :infos, :warnings, :debugs

    def initialize
      @infos = []
      @warnings = []
      @debugs = []
    end

    def info(payload)
      @infos << payload
    end

    def debug(payload = nil, &block)
      payload = block.call if block
      @debugs << payload
    end

    def warn(payload = nil, &block)
      payload = block.call if block
      @warnings << payload
    end
  end

  setup do
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    Distillator::FetchCache.delete_all
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
  end

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

  test "compact_refresh_error removes nested abort payload details from user message" do
    message = compact_refresh_error(
      error_type: "phantomjs_unavailable",
      step: "url",
      error: "Legacy PhantomJS renderer is unavailable",
      signals: {
        blocking_issue_key: "phantomjs_unavailable",
        renderer_fallback: "direct_url",
        primary_issue_category: "renderer",
        phantomjs_iframe_extraction: false
      },
      hints: ["legacy_phantomjs", "phantomjs_unavailable"]
    )

    assert_match "Scrape aborted (phantomjs_unavailable)", message
    assert_match "step=url", message
    assert_match "Legacy PhantomJS renderer is unavailable", message
    assert_no_match "renderer_fallback", message
    assert_no_match "primary_issue_category", message
    assert_no_match "phantomjs_iframe_extraction", message
  end

  test "refresh_statement_helper adds compact abort error without nested signals" do
    stat = statements(:one)

    self.stubs(:trace_enabled_for_request?).returns(false)
    self.stubs(:run_dsl).returns(
      ["abort_update", {
        error_type: "phantomjs_unavailable",
        error: "Legacy PhantomJS renderer is unavailable",
        step: "url",
        signals: {
          blocking_issue_key: "phantomjs_unavailable",
          renderer_fallback: "direct_url",
          primary_issue_category: "renderer",
          phantomjs_iframe_extraction: false
        },
        hints: ["legacy_phantomjs", "phantomjs_unavailable"]
      }]
    )

    result = refresh_statement_helper(stat)
    combined = result[:errors].join(" ")

    assert_match "phantomjs_unavailable", combined
    assert_no_match "renderer_fallback", combined
    assert_no_match "primary_issue_category", combined
    assert_no_match "phantomjs_iframe_extraction", combined
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
    expected_log_context = {
      statement_id: stat.id,
      source_id: stat.source_id,
      webpage_id: stat.webpage_id,
      website_id: stat.webpage.website_id
    }

    cookies[:dsl_trace] = "true"

    self.expects(:run_dsl).with(
      algorithm: stat.source.algorithm_value,
      render_js: stat.source.render_js,
      language: stat.source.language,
      url: stat.webpage.url,
      scrape_options: {
        json_post: stat.source.json_post?,
        use_phantomjs: stat.source.render_js,
        website: stat.source.website,
        website_id: stat.source.website_id,
        log_context: expected_log_context
      },
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
    expected_log_context = {
      statement_id: stat.id,
      source_id: stat.source_id,
      webpage_id: stat.webpage_id,
      website_id: stat.webpage.website_id
    }

    cookies[:dsl_trace] = "false"

    self.expects(:run_dsl).with(
      algorithm: stat.source.algorithm_value,
      render_js: stat.source.render_js,
      language: stat.source.language,
      url: stat.webpage.url,
      scrape_options: {
        json_post: stat.source.json_post?,
        use_phantomjs: stat.source.render_js,
        website: stat.source.website,
        website_id: stat.source.website_id,
        log_context: expected_log_context
      },
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

  test "refresh_statement_helper forwards force_scrape_every_hrs into dsl execution scrape options" do
    stat = statements(:one)
    run_result = ["first"]
    expected_log_context = {
      statement_id: stat.id,
      source_id: stat.source_id,
      webpage_id: stat.webpage_id,
      website_id: stat.webpage.website_id
    }

    self.stubs(:trace_enabled_for_request?).returns(false)
    self.expects(:run_dsl).with(
      algorithm: stat.source.algorithm_value,
      render_js: stat.source.render_js,
      language: stat.source.language,
      url: stat.webpage.url,
      scrape_options: {
        force_scrape_every_hrs: "1",
        json_post: stat.source.json_post?,
        use_phantomjs: stat.source.render_js,
        website: stat.source.website,
        website_id: stat.source.website_id,
        log_context: expected_log_context
      },
      trace: false
    ).returns(run_result)
    self.expects(:format_datatype).with(run_result, stat.source.property, stat.webpage).returns("formatted")
    self.stubs(:save_record?).returns(true)

    refresh_statement_helper(stat, force_scrape_every_hrs: "1")

    assert_equal "formatted", stat.reload.cache
  end

  test "statement_refresh_scrape_options always includes website_id" do
    stat = statements(:one)

    options = statement_refresh_scrape_options(stat, force_scrape_every_hrs: "1")

    assert_equal stat.source.json_post?, options[:json_post]
    assert_equal stat.source.render_js, options[:use_phantomjs]
    assert_equal stat.source.website, options[:website]
    assert_equal stat.source.website_id, options[:website_id]
    assert_equal stat.id, options.dig(:log_context, :statement_id)
    assert_equal stat.source_id, options.dig(:log_context, :source_id)
    assert_equal stat.webpage_id, options.dig(:log_context, :webpage_id)
    assert_equal stat.webpage.website_id, options.dig(:log_context, :website_id)
  end

  test "statement refresh in internal mode without explicit scrape options still uses Distillator fetch cache store" do
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    stat = statements(:one)
    stat.source.algorithm_value = "xpath=//h1/text()"
    stat.source.render_js = false
    stat.webpage.url = "https://example.com/refresh"

    self.stubs(:trace_enabled_for_request?).returns(false)
    self.expects(:format_datatype).with(["Title"], stat.source.property, stat.webpage).returns("formatted")
    self.stubs(:save_record?).returns(false)
    fetch = Struct.new(
      :status,
      :body,
      :html,
      :headers,
      :final_url,
      :redirect_chain,
      :http_response_code,
      :signals,
      :hints,
      :duration_ms,
      :cache_hit,
      :cache_write,
      :cache_reason,
      :uri_key,
      :normalized_url,
      :fetch_path,
      keyword_init: true
    ).new(
      status: :ok,
      body: "<html><body><h1>Title</h1></body></html>",
      html: "<html><body><h1>Title</h1></body></html>",
      headers: { content_type: "text/html" },
      final_url: "https://example.com/refresh",
      redirect_chain: ["https://example.com/refresh"],
      http_response_code: 200,
      signals: { "network_status" => "ok" },
      hints: [],
      duration_ms: 0,
      cache_hit: false,
      cache_write: true,
      cache_reason: "missing_cache",
      uri_key: CGI.escape("https://example.com/refresh"),
      normalized_url: "https://example.com/refresh",
      fetch_path: "native"
    )

    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal "https://example.com/refresh", kwargs[:uri]
      assert_equal false, kwargs[:render_js]
      assert_equal true, kwargs[:include_fragment]
      assert_equal false, kwargs[:json_post]
      assert_equal false, kwargs[:use_phantomjs]
      assert_equal stat.source.website, kwargs[:website]
      assert_equal stat.source.website_id, kwargs[:website_id]
      true
    end.returns(fetch)

    result = refresh_statement_helper(stat)

    assert_equal [], result[:errors]
    assert_equal ["Title"], result[:data]
  end

  test "refresh_statement_helper with crawl cache options writes distillator fetch cache for eligible native url" do
    stat = statements(:one)
    stat.source.algorithm_value = "xpath=//h1/text()"
    stat.source.render_js = false
    stat.webpage.url = "https://www.culture3r.com/evenements/gabrielle-caron-rodage/"
    html = "<html><body><h1>Gabrielle Caron</h1></body></html>"

    self.stubs(:trace_enabled_for_request?).returns(false)
    fetch = Struct.new(
      :status,
      :body,
      :html,
      :headers,
      :final_url,
      :redirect_chain,
      :http_response_code,
      :signals,
      :hints,
      :duration_ms,
      :cache_hit,
      :cache_write,
      :cache_reason,
      :uri_key,
      :normalized_url,
      :fetch_path,
      keyword_init: true
    ).new(
      status: :ok,
      body: html,
      html: html,
      headers: { content_type: "text/html" },
      final_url: stat.webpage.url,
      redirect_chain: [stat.webpage.url],
      http_response_code: 200,
      signals: {},
      hints: [],
      duration_ms: 0,
      cache_hit: false,
      cache_write: true,
      cache_reason: "stale_by_force_scrape_every_hrs",
      uri_key: CGI.escape(stat.webpage.url),
      normalized_url: stat.webpage.url,
      fetch_path: "native"
    )
    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal stat.webpage.url, kwargs[:uri]
      assert_equal false, kwargs[:render_js]
      assert_equal true, kwargs[:include_fragment]
      assert_equal "1", kwargs[:force_scrape_every_hrs]
      assert_equal stat.source.website, kwargs[:website]
      assert_equal stat.source.website_id, kwargs[:website_id]
      true
    end.returns(fetch)

    result = refresh_statement_helper(stat, force_scrape_every_hrs: "1")

    assert_equal [], result[:errors]
    assert_equal "Gabrielle Caron", stat.reload.cache
  end

  test "refresh_statement_helper passes render_js and json_post through Distillator fetch cache store" do
    stat = statements(:one)
    stat.source.algorithm_value = "xpath=//h1/text()"
    stat.source.render_js = true
    stat.webpage.url = "https://example.com/post"
    fetch = Struct.new(
      :status,
      :body,
      :html,
      :headers,
      :final_url,
      :redirect_chain,
      :http_response_code,
      :signals,
      :hints,
      :duration_ms,
      :cache_hit,
      :cache_write,
      :cache_reason,
      :uri_key,
      :normalized_url,
      :fetch_path,
      keyword_init: true
    ).new(
      status: :ok,
      body: "<html><body><h1>Title</h1></body></html>",
      html: "<html><body><h1>Title</h1></body></html>",
      headers: { content_type: "text/html" },
      final_url: stat.webpage.url,
      redirect_chain: [stat.webpage.url],
      http_response_code: 200,
      signals: {},
      hints: [],
      duration_ms: 0,
      cache_hit: false,
      cache_write: true,
      cache_reason: "stale_by_force_scrape_every_hrs",
      uri_key: CGI.escape(stat.webpage.url),
      normalized_url: stat.webpage.url,
      fetch_path: "legacy"
    )

    self.stubs(:trace_enabled_for_request?).returns(false)
    self.expects(:format_datatype).with(["Title"], stat.source.property, stat.webpage).returns("formatted")
    self.stubs(:save_record?).returns(false)
    Distillator::FetchCacheStore.expects(:fetch).with do |kwargs|
      assert_equal stat.webpage.url, kwargs[:uri]
      assert_equal true, kwargs[:render_js]
      assert_equal true, kwargs[:include_fragment]
      assert_equal true, kwargs[:json_post]
      assert_equal true, kwargs[:use_phantomjs]
      assert_equal "24", kwargs[:force_scrape_every_hrs]
      assert_equal stat.source.website, kwargs[:website]
      assert_equal stat.source.website_id, kwargs[:website_id]
      true
    end.returns(fetch)

    result = refresh_statement_helper(stat, json_post: true, force_scrape_every_hrs: "24")

    assert_equal [], result[:errors]
    assert_equal ["Title"], result[:data]
  end

  test "refresh_statement_helper preserves previous cache and skips formatting when distillator fetch aborts" do
    stat = statements(:one)
    stat.source.algorithm_value = "xpath=//h1/text()"
    stat.source.render_js = false
    stat.webpage.url = "https://example.com/failure"
    original_cache = stat.cache
    original_cache_refreshed = stat.cache_refreshed
    fetch = Struct.new(
      :status,
      :body,
      :html,
      :headers,
      :final_url,
      :redirect_chain,
      :http_response_code,
      :signals,
      :hints,
      :duration_ms,
      :cache_hit,
      :cache_write,
      :cache_reason,
      :uri_key,
      :normalized_url,
      :fetch_path,
      keyword_init: true
    ).new(
      status: :abort,
      body: ["abort_update", { error: "connection reset", error_type: "NativeFetchError", source: "native_fetch", retry: true, cache: false }],
      html: nil,
      headers: {},
      final_url: stat.webpage.url,
      redirect_chain: [],
      http_response_code: nil,
      signals: { "error_type" => "NativeFetchError", "network_status" => "failed" },
      hints: ["timeout"],
      duration_ms: 4.0,
      cache_hit: false,
      cache_write: true,
      cache_reason: "force_scrape",
      uri_key: CGI.escape(stat.webpage.url),
      normalized_url: stat.webpage.url,
      fetch_path: "native"
    )

    self.stubs(:trace_enabled_for_request?).returns(false)
    self.expects(:format_datatype).never
    self.expects(:save_record?).never
    Distillator::FetchCacheStore.expects(:fetch).returns(fetch)

    result = refresh_statement_helper(stat, force_scrape: true)

    assert_match(/Scrape aborted \(NativeFetchError\)/, result[:errors].join(" "))
    assert_equal original_cache, stat.reload.cache
    assert_equal original_cache_refreshed, stat.cache_refreshed
  end

  test "refresh_statement_helper does not replace statement cache with redirect listing title when content failed" do
    stat = statements(:one)
    stat.update!(cache: "Existing Event Title", cache_refreshed: 1.day.ago, status: "ok")
    stat.source.algorithm_value = "xpath=//title;ruby=$array.map{|e| e.gsub(/ \\|.*/,'')}"
    stat.source.render_js = true
    stat.webpage.url = "https://www.ovation.ca/00001Q/fr/Event/?seriesId=series&venueId=venue"

    fetch = Struct.new(
      :status,
      :body,
      :html,
      :headers,
      :final_url,
      :redirect_chain,
      :http_response_code,
      :signals,
      :hints,
      :duration_ms,
      :cache_hit,
      :cache_write,
      :cache_reason,
      :uri_key,
      :normalized_url,
      :fetch_path,
      keyword_init: true
    ) do
      def content_success?
        false
      end
    end.new(
      status: :ok,
      body: "<html><title>Recherche par titre</title></html>",
      html: nil,
      headers: { content_type: "text/html" },
      final_url: "https://www.ovation.ca/Search/Title/",
      redirect_chain: [stat.webpage.url, "https://www.ovation.ca/Search/Title/"],
      http_response_code: 200,
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "primary_issue_key" => "redirect_to_listing",
        "primary_issue_severity" => "failed",
        "blocking_issue_key" => "redirect_to_listing",
        "content_success" => false
      },
      hints: ["redirect_to_listing"],
      duration_ms: 0,
      cache_hit: false,
      cache_write: true,
      cache_reason: "force_scrape",
      uri_key: CGI.escape(stat.webpage.url),
      normalized_url: stat.webpage.url,
      fetch_path: "native"
    )

    self.stubs(:trace_enabled_for_request?).returns(false)
    self.expects(:format_datatype).never
    self.expects(:save_record?).never
    Distillator::FetchCacheStore.expects(:fetch).returns(fetch)

    result = refresh_statement_helper(stat, force_scrape: true)

    assert_match(/redirect_to_listing/, result[:errors].join(" "))
    assert_equal "Existing Event Title", stat.reload.cache
    assert_not_equal "Recherche par titre", stat.reload.cache
  end

  test "run_dsl content failure abort preserves retry and cache policy for phantomjs unavailable" do
    stat = statements(:one)
    fetch = Struct.new(
      :status,
      :body,
      :html,
      :headers,
      :final_url,
      :redirect_chain,
      :http_response_code,
      :signals,
      :hints,
      :duration_ms,
      :cache_hit,
      :cache_write,
      :cache_reason,
      :uri_key,
      :normalized_url,
      :fetch_path,
      keyword_init: true
    ) do
      def content_success?
        false
      end

      def retry_policy
        true
      end

      def cache_policy
        false
      end
    end.new(
      status: :abort,
      body: nil,
      html: nil,
      headers: {},
      final_url: stat.webpage.url,
      redirect_chain: [],
      http_response_code: nil,
      signals: {
        "network_status" => "failed",
        "renderer" => "legacy_phantomjs",
        "renderer_unavailable" => true,
        "blocking_issue_key" => "phantomjs_unavailable",
        "primary_issue_key" => "phantomjs_unavailable",
        "content_success" => false,
        "retry" => true,
        "cache" => false
      },
      hints: ["legacy_phantomjs", "phantomjs_unavailable"],
      duration_ms: 0,
      cache_hit: false,
      cache_write: true,
      cache_reason: "force_scrape",
      uri_key: CGI.escape(stat.webpage.url),
      normalized_url: stat.webpage.url,
      fetch_path: "native"
    )

    Distillator::FetchCacheStore.expects(:fetch).returns(fetch)

    result = run_dsl(
      algorithm: "xpath=//title",
      render_js: true,
      url: stat.webpage.url,
      scrape_options: {
        use_phantomjs: true,
        website: stat.source.website,
        website_id: stat.source.website_id,
        log_context: {
          statement_id: stat.id,
          source_id: stat.source_id,
          webpage_id: stat.webpage_id,
          website_id: stat.webpage.website_id
        }
      },
      trace: false
    )

    assert_equal "abort_update", result.first
    assert_equal "phantomjs_unavailable", result.last[:error_type]
    assert_equal true, result.last[:retry]
    assert_equal false, result.last[:cache]
  end

  test "refresh_statement_helper logs structured content failure context" do
    stat = statements(:one)
    stat.update!(cache: "Existing Event Title", cache_refreshed: 1.day.ago, status: "ok")
    stat.source.algorithm_value = "xpath=//title"
    logger = CapturingLogger.new
    fetch = Struct.new(
      :status,
      :body,
      :html,
      :headers,
      :final_url,
      :redirect_chain,
      :http_response_code,
      :signals,
      :hints,
      :duration_ms,
      :cache_hit,
      :cache_write,
      :cache_reason,
      :uri_key,
      :normalized_url,
      :fetch_path,
      keyword_init: true
    ) do
      def content_success?
        false
      end

      def retry_policy
        false
      end

      def cache_policy
        false
      end
    end.new(
      status: :ok,
      body: "<html><title>Recherche par titre</title></html>",
      html: nil,
      headers: { content_type: "text/html" },
      final_url: "https://www.ovation.ca/Search/Title/",
      redirect_chain: [stat.webpage.url, "https://www.ovation.ca/Search/Title/"],
      http_response_code: 200,
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "primary_issue_key" => "redirect_to_listing",
        "blocking_issue_key" => "redirect_to_listing",
        "content_success" => false
      },
      hints: ["redirect_to_listing"],
      duration_ms: 0,
      cache_hit: false,
      cache_write: true,
      cache_reason: "force_scrape",
      uri_key: CGI.escape(stat.webpage.url),
      normalized_url: stat.webpage.url,
      fetch_path: "native"
    )

    self.stubs(:trace_enabled_for_request?).returns(false)
    self.expects(:format_datatype).never
    self.expects(:save_record?).never
    Distillator::FetchCacheStore.expects(:fetch).returns(fetch)
    Rails.stubs(:logger).returns(logger)

    refresh_statement_helper(stat, force_scrape: true)

    warning = logger.warnings.find { |payload| payload.is_a?(Hash) && payload[:event] == "dsl.fetch.content_failure" }
    assert warning.present?
    assert_equal stat.webpage.url, warning[:url]
    assert_equal "redirect_to_listing", warning[:error_type]
    assert_equal "https://www.ovation.ca/Search/Title/", warning[:final_url]
    assert_equal 200, warning[:http_response_code]
    assert_equal false, warning[:cache_hit]
    assert_equal true, warning[:cache_write]
    assert_equal "force_scrape", warning[:cache_reason]
    assert_equal stat.id, warning[:statement_id]
    assert_equal stat.source_id, warning[:source_id]
    assert_equal stat.webpage_id, warning[:webpage_id]
    assert_equal stat.webpage.website_id, warning[:website_id]
  end

  test "wringer_links_for_step includes mode-aware active cache link without fetching" do
    previous_mode = ENV["DISTILLATOR_FETCH_MODE"]
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchCacheStore.expects(:fetch).never
    website = websites(:one)
    website.update!(distillator_mode: "active")

    links = wringer_links_for_step(
      url_after: "http://example.org/page",
      website_id: website.id,
      wringer: { signals: { network_status: "ok" } }
    )

    assert_match "/websites?term=", links[:wringer_search]
    assert_equal "http://example.org/page", links[:raw_url]
    assert_equal "/condenser/cache?term=http%3A%2F%2Fexample.org%2Fpage", links.dig(:active_cache, :active_cache_url)
    assert_equal "Inspect legacy Wringer", links.dig(:active_cache, :secondary_links, 0, :label)
  ensure
    ENV["DISTILLATOR_FETCH_MODE"] = previous_mode
  end

  test "run_dsl returns [result, trace] when trace is enabled" do
    runner = mock("dsl_runner")
    runner.expects(:run).with("manual=hello").returns(["hello"])

    Dsl::Core::AlgorithmRunner.expects(:new).with do |ctx|
      assert_equal "https://example.com", ctx[:url]
      assert_equal false, ctx[:render_js]
      assert_equal({}, ctx[:scrape_options])
      assert_instance_of Dsl::Tracing::TraceCollector, ctx[:tracer]
      true
    end.returns(runner)

    assert_equal [["hello"], []], run_dsl(algorithm: "manual=hello", url: "https://example.com", trace: true)
  end

  test "run_dsl returns result only when trace is disabled" do
    runner = mock("dsl_runner")
    runner.expects(:run).with("manual=hello").returns(["hello"])

    Dsl::Core::AlgorithmRunner.expects(:new).with do |ctx|
      assert_equal "https://example.com", ctx[:url]
      assert_equal false, ctx[:render_js]
      assert_equal({}, ctx[:scrape_options])
      assert_instance_of Dsl::Tracing::NullTracer, ctx[:tracer]
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

  test "interactive_redirect_info returns redirected with final_url" do
    step = {
      url_before: "https://example.com/start",
      wringer: {
        final_url: "https://example.com/final"
      }
    }

    assert_equal "Network: redirected -> https://example.com/final", interactive_redirect_info(step)
    assert_equal "Network: redirected -> https://example.com/final", wringer_network_metadata(step)
  end

  test "interactive_redirect_info falls back to signals final_url" do
    step = {
      url_after: "https://example.com/base",
      wringer: {
        signals: {
          final_url: "https://example.com/from-signals"
        }
      }
    }

    assert_equal "Network: redirected -> https://example.com/from-signals", interactive_redirect_info(step)
  end

  test "interactive_redirect_info reports redirect when only redirect_chain is present" do
    step = {
      url_after: "https://example.com/base",
      wringer: {
        redirect_chain: ["https://example.com/step-1"],
        final_url: nil
      }
    }

    assert_equal "Network: redirected", interactive_redirect_info(step)
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
