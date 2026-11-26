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

  test "one warm statement uses the selected backend through diagnostics, promotion and rollback" do
    statement = build_statement_for_rollout(mode: "legacy", slug: "warm-switch")
    page = statement.webpage
    website = page.website
    uri = page.url
    native = fetch_result("<title>Condenser title</title>", url: uri)
    legacy = fetch_result("<title>Wringer title</title>", url: uri, fetch_path: "legacy")
    unavailable = {
      status: :abort, body: ["abort_update", { error: "Wringer unavailable" }],
      http_code: 503, headers: {}, wringer: { signals: { transport_success: false, content_success: false } }
    }
    Distillator::FetchService.expects(:internal_fetch).times(4).returns(native)
    Distillator::FetchService.expects(:legacy_fetch).times(5).returns(legacy, legacy, unavailable, legacy, legacy)

    # A diagnostic candidate may write the same cache row that serving later reads.
    Distillator::FetchCacheStore.fetch(uri: uri, website: website, mode: :internal, force_scrape: true)
    fetch_cache = Distillator::FetchCache.find_by!(normalized_url: uri)
    assert_equal "native", fetch_cache.signals.dig("body_profile", "backend")
    patch refresh_statement_path(statement)
    assert_equal "Wringer title", statement.reload.cache
    assert_equal "legacy", fetch_cache.reload.signals.dig("body_profile", "backend")

    patch website_path(website), params: { website: { distillator_mode: "shadow" } }
    assert_equal "shadow", website.reload.distillator_mode
    Distillator::FetchCacheStore.fetch(uri: uri, website: website, mode: :internal, force_scrape: true)
    patch refresh_statement_path(statement)
    assert_equal "Wringer title", statement.reload.cache
    assert_equal "legacy", fetch_cache.reload.signals.dig("body_profile", "backend")
    assert_logged_context!("fetch.shadow_compare", statement)

    publish_transition_fixture(website, defaults: {
      "fetch_parity" => { status: "checked" },
      "statement_delta" => { status: "checked", statement_count_delta_acceptable: true },
      "export_diff" => { status: "checked", export_diff_checked: true }
    })
    patch website_path(website), params: { website: { distillator_mode: "active" } }
    assert_equal "active", website.reload.distillator_mode
    patch refresh_statement_path(statement)
    assert_equal "Condenser title", statement.reload.cache
    assert_equal "native", fetch_cache.reload.signals.dig("body_profile", "backend")
    last_good_statement_refresh = statement.cache_refreshed
    last_good_native_html = fetch_cache.html
    last_good_native_refresh = fetch_cache.successful_refresh

    patch website_path(website), params: { website: { distillator_mode: "legacy" } }
    assert_equal "legacy", website.reload.distillator_mode
    patch refresh_statement_path(statement, format: :json)
    assert_response :unprocessable_entity
    assert_equal "http_5xx", JSON.parse(response.body).fetch("error_type")
    assert_equal last_good_native_html, fetch_cache.reload.html
    assert_equal last_good_native_refresh, fetch_cache.successful_refresh
    assert_equal "native", fetch_cache.signals.dig("body_profile", "backend")
    assert_equal true, fetch_cache.signals["last_good_preserved_failure"]
    assert_equal 503, fetch_cache.http_response_code
    assert_equal last_good_statement_refresh, statement.reload.cache_refreshed
    assert_equal "Condenser title", statement.cache

    patch refresh_statement_path(statement)
    assert_equal "Wringer title", statement.reload.cache
    assert_equal "legacy", fetch_cache.reload.signals.dig("body_profile", "backend")
    assert_equal legacy[:body], fetch_cache.html
    assert_equal %w[shadow active legacy], website.rollout_events.order(:id).pluck(:to_mode)

    unverified_body = "<title>Unverified cached title</title>"
    fetch_cache.update_columns(html: unverified_body, body: unverified_body, signals: fetch_cache.signals.except("body_profile"))
    patch refresh_statement_path(statement)
    assert_equal "Wringer title", statement.reload.cache
    assert_equal legacy[:body], fetch_cache.reload.html
    assert_equal "legacy", fetch_cache.signals.dig("body_profile", "backend")
  end

  test "ordinary Wringer refresh raises one monitoring issue for a repeated upstream 403 with retained HTML" do
    statement = build_statement_for_rollout(mode: "legacy", slug: "blocked-wringer")
    website = statement.webpage.website
    website.update!(monitorable: true)
    uri = statement.webpage.url
    previous_success = Time.iso8601("2026-09-28T21:13:16Z")
    attempt = Time.iso8601("2026-11-19T19:31:06Z")
    recovered_at = attempt + 1.hour
    retained = fetch_result("<title>Last good event</title>", url: uri, fetch_path: "legacy")
    blocked = retained.merge(headers: retained[:headers].merge("X-Wringer-Upstream-Status" => ["403"],
      "X-Wringer-Last-Attempt-At" => [attempt.iso8601], "X-Wringer-Last-Success-At" => [previous_success.iso8601]))
    recovered = retained.merge(headers: retained[:headers].merge("X-Wringer-Upstream-Status" => "200",
      "X-Wringer-Last-Attempt-At" => recovered_at.iso8601, "X-Wringer-Last-Success-At" => recovered_at.iso8601))
    Distillator::FetchService.expects(:legacy_fetch).times(4).returns(blocked, blocked, retained, recovered)

    patch refresh_statement_path(statement)
    assert_equal "Last good event", statement.reload.cache
    issues = MonitoringIssue.where(kind: "blocked_fetch", seedurl: website.seedurl)
    issue = issues.open_issues.sole
    assert_equal attempt, issue.last_seen_at
    assert_includes issue.message, "Wringer reported HTTP 403"
    assert_includes issue.message, "2026-09-28T21:13:16Z"
    assert_includes issue.message, "Cached HTML remains available"

    2.times { ApplicationController.helpers.refresh_statement_helper(statement, force_scrape: true) }
    assert_equal 1, issue.reload.occurrences
    assert_nil issue.resolved_at
    get monitoring_path(format: :json), params: { seedurl: website.seedurl }
    assert_equal issue.message, JSON.parse(response.body).fetch("issues").sole.fetch("message")

    ApplicationController.helpers.refresh_statement_helper(statement, force_scrape: true)
    assert_equal recovered_at, issue.reload.resolved_at
  end

  test "a Condenser challenge enters monitoring only through an ordinary monitored refresh" do
    statement = build_statement_for_rollout(mode: "active", slug: "blocked-condenser")
    website = statement.webpage.website
    website.update!(monitorable: true)
    uri = statement.webpage.url
    blocked = fetch_result("<title>Challenge</title>", url: uri).merge(http_code: 403,
      headers: { "CF-Ray" => "1234abcdef567890-YYZ", "CF-Mitigated" => "challenge" })
    Distillator::FetchService.expects(:internal_fetch).twice.returns(blocked)
    issues = MonitoringIssue.where(kind: "blocked_fetch", seedurl: website.seedurl)

    Distillator::FetchCacheStore.fetch(uri: uri, website: website, mode: :internal, force_scrape: true)
    assert_empty issues
    ApplicationController.helpers.refresh_statement_helper(statement, force_scrape: true)

    issue = issues.open_issues.sole
    assert_includes issue.message, "Condenser reported Cloudflare challenge (HTTP 403)"
    assert_includes issue.message, "CF-Ray 1234abcdef567890-YYZ"
    assert_includes issue.message, "Last successful source refresh not recorded"
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
