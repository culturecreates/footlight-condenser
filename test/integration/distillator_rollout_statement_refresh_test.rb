require "test_helper"

class DistillatorRolloutStatementRefreshTest < ActionDispatch::IntegrationTest
  class CapturingLogger < ::Logger
    attr_reader :infos, :warnings, :debugs

    def initialize
      super(StringIO.new)
      @infos = []
      @warnings = []
      @debugs = []
    end

    def info(payload = nil, &block)
      payload = block.call if block
      @infos << payload
      super(payload)
    end

    def warn(payload = nil, &block)
      payload = block.call if block
      @warnings << payload
      super(payload)
    end

    def debug(payload = nil, &block)
      payload = block.call if block
      @debugs << payload
      super(payload)
    end
  end

  setup do
    Distillator::FetchCache.delete_all
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::FetchGuard.stubs(:check_response).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::WringerEndpoint.stubs(:current).returns(
      Distillator::WringerEndpoint::Result.new(
        compatibility_base_url: "https://wringer.example",
        legacy_lookup_base_url: "https://wringer.example",
        compatibility_source: Distillator::WringerEndpoint::CANONICAL_COMPATIBILITY_ENV,
        state: :remote_configured,
        status_label: "Current Wringer: Remote configured",
        status_detail: "https://wringer.example"
      )
    )
    @logger = CapturingLogger.new
    Rails.stubs(:logger).returns(@logger)
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
  end

  test "active website refresh uses Distillator native fetch and trace links show legacy inspection" do
    statement = build_statement_for_rollout(mode: "active", slug: "active")

    Distillator::FetchService.expects(:internal_fetch).once.returns(fetch_result("<html><title>Active Title</title></html>", url: statement.webpage.url))
    Distillator::FetchService.expects(:legacy_fetch).never

    patch refresh_statement_path(statement), headers: trace_headers
    assert_redirected_to statement_url(statement)
    follow_redirect_with_trace_visibility("always", "3")

    assert_response :success
    assert_equal "Active Title", statement.reload.cache
    assert_includes response.body, "Open active cache"
    assert_includes response.body, "Inspect legacy Wringer"
    refute_includes response.body, "Shadow: Wringer serves production while Condenser is checked in the background."
    assert_logged_context!("fetch.native", statement)
    assert_logged_context!("cache.miss", statement)
  end

  test "shadow website refresh returns legacy body and records comparison with website context" do
    statement = build_statement_for_rollout(mode: "shadow", slug: "shadow")
    original_selected = statement.source.selected
    original_selected_by = statement.source.selected_by
    original_status = statement.status
    original_status_origin = statement.status_origin

    Distillator::FetchService.expects(:legacy_fetch).once.returns(fetch_result("<html><title>Legacy Shadow</title></html>", url: statement.webpage.url, fetch_path: "legacy"))
    Distillator::FetchService.expects(:internal_fetch).once.returns(fetch_result("<html><title>Internal Shadow</title></html>", url: statement.webpage.url))
    Distillator::FetchShadowComparator.expects(:compare).once

    patch refresh_statement_path(statement), headers: trace_headers
    assert_redirected_to statement_url(statement)
    follow_redirect_with_trace_visibility("always", "3")

    assert_response :success
    assert_equal "Legacy Shadow", statement.reload.cache
    refute_equal "Internal Shadow", statement.cache
    assert_equal original_status, statement.status
    assert_equal original_status_origin, statement.status_origin
    assert_equal original_selected, statement.source.reload.selected
    assert_equal original_selected_by, statement.source.selected_by
    assert_includes response.body, "Compare Condenser vs Wringer"
    assert_includes response.body, "Wringer serves production while Condenser is checked in the background."
    assert_logged_context!("fetch.shadow_compare", statement)
  end

  test "legacy website refresh keeps legacy path and renders legacy warning" do
    statement = build_statement_for_rollout(mode: "legacy", slug: "legacy")

    Distillator::FetchService.expects(:legacy_fetch).once.returns(fetch_result("<html><title>Legacy Title</title></html>", url: statement.webpage.url, fetch_path: "legacy"))
    Distillator::FetchService.expects(:internal_fetch).never

    patch refresh_statement_path(statement), headers: trace_headers
    assert_redirected_to statement_url(statement)
    follow_redirect_with_trace_visibility("always", "3")

    assert_response :success
    assert_equal "Legacy Title", statement.reload.cache
    assert_includes response.body, "Wringer serves production."
    assert_logged_context!("cache.miss", statement)
    assert_logged_context!("fetch.legacy", statement)
  end

  private

  def build_statement_for_rollout(mode:, slug:)
    website = Website.create!(
      name: "rollout-#{slug}",
      seedurl: "rollout-#{slug}",
      graph_name: "http://example.com/rollout-#{slug}",
      default_language: "en",
      distillator_mode: mode
    )
    webpage = Webpage.create!(
      url: "https://example.com/#{slug}",
      language: "en",
      rdf_uri: "http://example.com/rdf/#{slug}",
      rdfs_class: rdfs_classes(:one),
      website: website
    )
    source = Source.create!(
      algorithm_value: "url='#{webpage.url}';xpath=//title/text()",
      selected: true,
      selected_by: "test",
      language: "en",
      render_js: false,
      property: properties(:two),
      website: website
    )
    Statement.create!(
      cache: "old",
      status: "initial",
      status_origin: "test",
      cache_refreshed: 1.day.ago,
      cache_changed: 1.day.ago,
      source: source,
      webpage: webpage
    )
  end

  def fetch_result(body, url:, fetch_path: "native")
    {
      status: :ok,
      body: body,
      raw_body: body,
      headers: { content_type: "text/html" },
      final_url: url,
      redirect_chain: [url],
      wringer: { signals: {}, hints: [] },
      http_code: 200,
      fetch_path: fetch_path
    }
  end

  def trace_headers
    { "Cookie" => "dsl_trace=true; trace_visibility=always" }
  end

  def follow_redirect_with_trace_visibility(visibility, mode)
    get response.redirect_url, headers: { "Cookie" => "trace_visibility=#{visibility}; trace_view_mode=#{mode}" }
  end

  def assert_logged_context!(event_name, statement)
    payload = @logger.infos.find { |entry| entry.is_a?(Hash) && entry[:event] == event_name }
    assert payload, "Expected log event #{event_name.inspect}, got #{@logger.infos.map { |entry| entry[:event] if entry.is_a?(Hash) }.compact.inspect}"
    assert_equal statement.id, payload[:statement_id]
    assert_equal statement.source_id, payload[:source_id]
    assert_equal statement.webpage_id, payload[:webpage_id]
    assert_equal statement.webpage.website_id, payload[:website_id]
  end
end
