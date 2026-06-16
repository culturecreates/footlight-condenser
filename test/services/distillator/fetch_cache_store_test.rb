require "test_helper"

class Distillator::FetchCacheStoreTest < ActiveSupport::TestCase
  class CapturingLogger
    attr_reader :infos

    def initialize
      @infos = []
    end

    def info(payload)
      @infos << payload
    end
  end

  setup do
    Distillator::FetchCache.delete_all
    @old_rendered_fallback = ENV["DISTILLATOR_ALLOW_RENDERED_DIRECT_FALLBACK"]
  end

  teardown do
    ENV["DISTILLATOR_ALLOW_RENDERED_DIRECT_FALLBACK"] = @old_rendered_fallback
  end

  test "cache miss creates a distillator fetch cache and returns metadata-rich payload" do
    Distillator::FetchService.expects(:fetch_result).with do |kwargs|
      assert_equal "http://example.org/page", kwargs[:url]
      assert_equal false, kwargs[:render_js]
      assert_equal :internal, kwargs[:mode]
      true
    end.returns(success_result(body: "<html><title>Hello</title>Body</html>", final_url: "https://example.org/final", fetch_path: "native"))

    result = Distillator::FetchCacheStore.fetch(uri: "example.org/page", mode: :internal)
    cache = Distillator::FetchCache.find_by(uri_key: result.uri_key)

    assert cache
    assert_equal :ok, result.status
    assert_equal "<html><title>Hello</title>Body</html>", result.body
    assert_equal "<html><title>Hello</title>Body</html>", result.html
    assert_equal 200, result.http_response_code
    assert_equal false, result.cache_hit
    assert_equal true, result.cache_write
    assert_equal "missing_cache", result.cache_reason
    assert_equal "native", result.fetch_path
    assert_equal "http://example.org/page", result.normalized_url
    assert_equal ["https://example.org/final"], result.redirect_chain
    assert_equal "https://example.org/final", cache.final_url
    assert_equal "<html><title>Hello</title>Body</html>", cache.html
    assert_equal "healthy", cache.health_status
    assert_equal "html", cache.content_type
    assert_equal "ok", cache.network_status
    assert_equal "native", cache.signals["fetch_backend"]
    assert_equal "GET", cache.signals["request_method"]
    assert_equal false, cache.signals["use_phantomjs"]
  end

  test "website rollout context is forwarded to fetch service" do
    website = websites(:one)
    website.update!(distillator_mode: "active")

    Distillator::FetchService.expects(:fetch_result).with do |kwargs|
      assert_nil kwargs[:mode]
      assert_equal website, kwargs[:website]
      assert_equal website.id, kwargs[:website_id]
      true
    end.returns(success_result(body: "<html><title>Hello</title>Body</html>", fetch_path: "native"))

    result = Distillator::FetchCacheStore.fetch(
      uri: "https://example.org/context",
      website: website,
      website_id: website.id
    )

    assert_equal :ok, result.status
    assert_equal "native", result.fetch_path
  end

  test "fetch cache store persists the exact wringer-compatible uri key" do
    Distillator::FetchService.expects(:fetch_result).returns(success_result(body: "<html><title>Hello</title></html>", fetch_path: "native"))

    result = Distillator::FetchCacheStore.fetch(uri: "culturecreates.com/people/")

    assert_equal "http%3A%2F%2Fculturecreates.com%2Fpeople%2F", result.uri_key
    assert_equal ["http%3A%2F%2Fculturecreates.com%2Fpeople%2F"], Distillator::FetchCache.pluck(:uri_key)
  end

  test "cache fetch forwards structured log context to fetch service and logs cache events" do
    logger = CapturingLogger.new
    Distillator::FetchService.expects(:fetch_result).with do |kwargs|
      assert_equal({ statement_id: 7, source_id: 8, webpage_id: 9, website_id: 10 }, kwargs[:log_context])
      true
    end.returns(success_result(body: "<html><title>Hello</title>Body</html>", fetch_path: "legacy"))

    Distillator::FetchCacheStore.fetch(
      uri: "https://example.org/context",
      mode: :internal,
      logger: logger,
      log_context: { statement_id: 7, source_id: 8, webpage_id: 9, website_id: 10 }
    )

    assert_equal "cache.miss", logger.infos.first[:event]
    assert_equal 7, logger.infos.last[:statement_id]
    assert_equal 8, logger.infos.last[:source_id]
    assert_equal 9, logger.infos.last[:webpage_id]
    assert_equal 10, logger.infos.first[:website_id]
    assert_equal 10, logger.infos.last[:website_id]
    assert_equal "legacy", logger.infos.last[:fetch_path]
  end

  test "fresh cache hit does not fetch" do
    cache = create_cache(scrape_date: 10.minutes.ago, successful_refresh: 10.minutes.ago)
    Distillator::FetchService.expects(:fetch_result).never
    logger = CapturingLogger.new

    result = Distillator::FetchCacheStore.fetch(
      uri: cache.normalized_url,
      logger: logger,
      log_context: { statement_id: 1, source_id: 2, webpage_id: 3, website_id: 4 }
    )

    assert_equal :ok, result.status
    assert_equal true, result.cache_hit
    assert_equal false, result.cache_write
    assert_equal "fresh_cache", result.cache_reason
    assert_equal "cache", result.fetch_path
    assert_equal cache.html, result.html
    assert_equal cache.body, result.body
    assert_equal "cache.hit", logger.infos.first[:event]
    assert_equal 4, logger.infos.first[:website_id]
  end

  test "force_scrape true refreshes even when cache exists" do
    cache = create_cache(scrape_date: 10.minutes.ago, successful_refresh: 10.minutes.ago, html: "<html>old</html>")
    Distillator::FetchService.expects(:fetch_result).returns(success_result(body: "<html><title>New</title></html>"))
    logger = CapturingLogger.new

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape: true, logger: logger)

    assert_equal false, result.cache_hit
    assert_equal true, result.cache_write
    assert_equal "force_scrape", result.cache_reason
    assert_equal "<html><title>New</title></html>", result.html
    assert_equal "cache.refresh", logger.infos.last[:event]
  end

  test "force_scrape string false does not refresh an existing cache" do
    cache = create_cache(scrape_date: 10.minutes.ago, successful_refresh: 10.minutes.ago)
    Distillator::FetchService.expects(:fetch_result).never

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape: "false")

    assert_equal true, result.cache_hit
    assert_equal false, result.cache_write
    assert_equal "fresh_cache", result.cache_reason
    assert_equal cache.html, result.html
  end

  test "missing scrape_date refreshes and reports missing_scrape_date" do
    cache = create_cache(scrape_date: nil, successful_refresh: 10.minutes.ago)
    Distillator::FetchService.expects(:fetch_result).returns(success_result(body: "<html>missing scrape date</html>"))

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url)

    assert_equal false, result.cache_hit
    assert_equal true, result.cache_write
    assert_equal "missing_scrape_date", result.cache_reason
    assert_equal "<html>missing scrape date</html>", result.html
  end

  test "force_scrape_every_hrs zero refreshes" do
    cache = create_cache(scrape_date: 5.minutes.ago, successful_refresh: 5.minutes.ago)
    Distillator::FetchService.expects(:fetch_result).returns(success_result(body: "<html>zero refresh</html>"))

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape_every_hrs: "0")
    cache.reload

    assert_equal "stale_by_force_scrape_every_hrs", result.cache_reason
    assert_equal "<html>zero refresh</html>", result.html
    assert_equal "<html>zero refresh</html>", cache.html
    assert_equal "<html>zero refresh</html>", cache.body
    assert_equal result.uri_key, cache.uri_key
  end

  test "old cache refreshes when older than threshold" do
    cache = create_cache(scrape_date: 3.hours.ago, successful_refresh: 3.hours.ago)
    Distillator::FetchService.expects(:fetch_result).returns(success_result(body: "<html>stale refresh</html>"))

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape_every_hrs: "1")

    assert_equal "stale_by_force_scrape_every_hrs", result.cache_reason
    assert_equal "<html>stale refresh</html>", result.html
  end

  test "successful 2xx response updates successful_refresh" do
    cache = create_cache(scrape_date: 2.days.ago, successful_refresh: 2.days.ago)
    previous_success = cache.successful_refresh
    Distillator::FetchService.expects(:fetch_result).returns(success_result(body: "<html><title>Fresh</title></html>", http_code: 201))

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape: true)

    assert_equal 201, result.http_response_code
    assert_operator result.successful_refresh, :>, previous_success
    assert_equal "<html><title>Fresh</title></html>", result.html
  end

  test "rendered fetch fallback to direct listing redirect is not a successful refresh" do
    ENV["DISTILLATOR_ALLOW_RENDERED_DIRECT_FALLBACK"] = "true"
    ovation_url = "https://www.ovation.ca/00001Q/fr/Event/?seriesId=series&venueId=venue"
    listing_url = "https://www.ovation.ca/Search/Title/"
    listing_html = "<html><head><title>Recherche par titre</title></head><body>Recherche par titre</body></html>"

    Distillator::FetchService.expects(:fetch_result).with do |kwargs|
      assert_equal true, kwargs[:render_js]
      true
    end.returns(
      success_result(
        body: listing_html,
        headers: { content_type: "text/html" },
        signals: {
          network_status: "ok",
          content_type: "html",
          renderer: "legacy_phantomjs",
          renderer_unavailable: true,
          renderer_fallback: "direct_url",
          primary_issue_key: "redirect_to_listing",
          primary_issue_severity: "failed",
          primary_issue_category: "redirect",
          primary_issue_label: "Redirect to listing",
          blocking_issue_key: "redirect_to_listing",
          content_success: false,
          transport_success: true
        },
        hints: %w[legacy_phantomjs phantomjs_unavailable redirect_to_listing],
        http_code: 200,
        final_url: listing_url,
        redirect_chain: [ovation_url, listing_url],
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(uri: ovation_url, render_js: true, use_phantomjs: true, mode: :internal, force_scrape: true)
    cache = Distillator::FetchCache.find_by(uri_key: result.uri_key)

    assert_equal true, result.transport_success?
    assert_equal false, result.content_success?
    assert_equal true, result.blocking_issue?
    assert_equal "redirect_to_listing", result.blocking_issue_key
    assert_equal "redirect_to_listing", cache.primary_issue_key
    assert_equal true, cache.signals["renderer_unavailable"]
    assert_equal "direct_url", cache.signals["renderer_fallback"]
    assert_nil cache.successful_refresh
    assert_equal "attempt_failed", cache.health_status
  end

  test "non 2xx response updates scrape_date and http_response_code but preserves last good html" do
    old_scrape_date = 2.days.ago
    old_successful_refresh = 2.hours.ago
    cache = create_cache(
      scrape_date: old_scrape_date,
      successful_refresh: old_successful_refresh,
      html: "<html>last good</html>",
      body: "<html>last good</html>"
    )
    Distillator::FetchService.expects(:fetch_result).returns(
      abort_result(
        http_code: 500,
        raw_body: "<html><title>Server Error</title></html>",
        headers: { content_type: "text/html" },
        signals: { network_status: "ok" },
        hints: [],
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape: true)

    assert_equal :ok, result.status
    assert_equal 500, result.http_response_code
    assert_equal "<html>last good</html>", result.html
    assert_equal "<html>last good</html>", result.body
    assert_equal old_successful_refresh.to_i, result.successful_refresh.to_i
    assert_operator result.scrape_date, :>, old_scrape_date
    assert_equal "Server Error", result.name
  end

  test "404 response preserves last good html body and successful_refresh while updating failure metadata" do
    old_scrape_date = 2.days.ago
    old_successful_refresh = 3.hours.ago
    cache = create_cache(
      scrape_date: old_scrape_date,
      successful_refresh: old_successful_refresh,
      html: "<html>last good</html>",
      body: "<html>last good</html>",
      signals: { "network_status" => "ok", "content_type" => "html" },
      hints: []
    )

    Distillator::FetchService.expects(:fetch_result).returns(
      abort_result(
        http_code: 404,
        raw_body: "<html><title>Not Found</title></html>",
        headers: { content_type: "text/html" },
        signals: { network_status: "ok", content_type: "html" },
        hints: ["not_found"],
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape: true)
    cache.reload

    assert_equal :ok, result.status
    assert_equal 404, result.http_response_code
    assert_equal "<html>last good</html>", result.html
    assert_equal "<html>last good</html>", result.body
    assert_equal old_successful_refresh.to_i, result.successful_refresh.to_i
    assert_operator result.scrape_date, :>, old_scrape_date
    assert_includes result.hints, "not_found"
    assert_includes result.hints, "last_good_preserved_failure"
    assert_equal "ok", result.signals["network_status"]
    assert_equal "Not Found", cache.name
  end

  test "timeout abort preserves last good html body and successful_refresh while updating abort metadata" do
    old_scrape_date = 2.days.ago
    old_successful_refresh = 4.hours.ago
    cache = create_cache(
      scrape_date: old_scrape_date,
      successful_refresh: old_successful_refresh,
      html: "<html>last good</html>",
      body: "<html>last good</html>",
      name: "Last Good"
    )

    Distillator::FetchService.expects(:fetch_result).returns(
      {
        status: :abort,
        body: ["abort_update", { error: "execution expired", error_type: "TimeoutError" }],
        raw_body: nil,
        headers: {},
        final_url: cache.normalized_url,
        redirect_chain: [],
        wringer: {
          error_type: "TimeoutError",
          signals: { network_status: "failed", timeout: true },
          hints: ["timeout"]
        },
        http_code: nil,
        duration_ms: 8.0,
        fetch_path: "native"
      }
    )

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape: true)
    cache.reload

    assert_equal :ok, result.status
    assert_nil result.http_response_code
    assert_equal "<html>last good</html>", result.html
    assert_equal "<html>last good</html>", result.body
    assert_equal old_successful_refresh.to_i, result.successful_refresh.to_i
    assert_operator result.scrape_date, :>, old_scrape_date
    assert_equal "failed", result.signals["network_status"]
    assert_includes result.hints, "timeout"
    assert_includes result.hints, "last_good_preserved_failure"
    assert_equal "Last Good", cache.name
  end

  test "blocked abort preserves last good html body and successful_refresh while updating blocked metadata" do
    old_scrape_date = 2.days.ago
    old_successful_refresh = 5.hours.ago
    cache = create_cache(
      uri: "http://example.org/blocked",
      scrape_date: old_scrape_date,
      successful_refresh: old_successful_refresh,
      html: "<html>last good</html>",
      body: "<html>last good</html>",
      name: "Last Good"
    )

    Distillator::FetchService.expects(:fetch_result).returns(
      {
        status: :abort,
        body: ["abort_update", { error: "Blocked localhost host: 127.0.0.1", error_type: "DistillatorFetchBlocked" }],
        raw_body: nil,
        headers: {},
        final_url: cache.normalized_url,
        redirect_chain: [],
        wringer: {
          error_type: "DistillatorFetchBlocked",
          signals: { network_status: "blocked", native_ineligible_reason: "blocked_url" },
          hints: ["blocked_url", "blocked"]
        },
        http_code: nil,
        duration_ms: 1.0,
        fetch_path: "blocked"
      }
    )

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape: true)
    cache.reload

    assert_equal :ok, result.status
    assert_nil result.http_response_code
    assert_equal "<html>last good</html>", result.html
    assert_equal "<html>last good</html>", result.body
    assert_equal old_successful_refresh.to_i, result.successful_refresh.to_i
    assert_operator result.scrape_date, :>, old_scrape_date
    assert_equal "blocked", result.signals["network_status"]
    assert_equal "blocked_url", result.signals["native_ineligible_reason"]
    assert_includes result.hints, "blocked_url"
    assert_includes result.hints, "blocked"
    assert_includes result.hints, "last_good_preserved_failure"
    assert_equal "Last Good", cache.name
  end

  test "policy abort with http 200 body preserves last good content and marks failed content semantics" do
    old_scrape_date = 2.days.ago
    old_successful_refresh = 6.hours.ago
    cache = create_cache(
      uri: "https://www.ovation.ca/event",
      scrape_date: old_scrape_date,
      successful_refresh: old_successful_refresh,
      html: "<html>last good</html>",
      body: "<html>last good</html>",
      name: "Last Good"
    )

    Distillator::FetchService.expects(:fetch_result).returns(
      {
        status: :ok,
        body: "<html><title>Recherche par titre</title></html>",
        raw_body: "<html><title>Recherche par titre</title></html>",
        headers: { content_type: "text/html" },
        final_url: "https://www.ovation.ca/Search/Title/",
        redirect_chain: [cache.normalized_url, "https://www.ovation.ca/Search/Title/"],
        wringer: {
          policy_action: "abort_update",
          retry: false,
          cache: false,
          signals: {
            network_status: "ok",
            content_type: "html",
            primary_issue_key: "redirect_to_listing",
            primary_issue_severity: "failed"
          },
          hints: ["redirect_to_listing"]
        },
        http_code: 200,
        duration_ms: 3.0,
        fetch_path: "native"
      }
    )

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape: true)
    cache.reload

    assert_equal :ok, result.status
    assert_equal true, result.transport_success?
    assert_equal false, result.content_success?
    assert_equal "<html>last good</html>", result.html
    assert_equal "<html>last good</html>", result.body
    assert_equal old_successful_refresh.to_i, result.successful_refresh.to_i
    assert_operator result.scrape_date, :>, old_scrape_date
    assert_includes result.hints, "last_good_preserved_failure"
    assert_equal true, result.signals["last_good_preserved_failure"]
    assert_equal "abort_update", result.signals["policy_action"]
    assert_equal false, result.signals["cache"]
    assert_equal old_successful_refresh.to_i, cache.successful_refresh.to_i
  end

  test "rendered payload includes cache metadata for legacy refreshes too" do
    Distillator::FetchService.expects(:fetch_result).with do |kwargs|
      assert_equal true, kwargs[:render_js]
      assert_equal true, kwargs[:scrape_options][:json_post]
      true
    end.returns(
      success_result(
        body: '{"ok":true}',
        headers: { content_type: "application/json" },
        signals: { network_status: "ok", content_type: "json", json_detected: true },
        hints: ["json_detected"],
        http_code: 200,
        fetch_path: "legacy"
      )
    )

    result = Distillator::FetchCacheStore.fetch(
      uri: "http://example.org/api",
      render_js: true,
      json_post: true,
      mode: :legacy
    )

    assert_equal "legacy", result.fetch_path
    assert_equal false, result.cache_hit
    assert_equal true, result.cache_write
    assert_equal '{"ok":true}', result.body
    assert_equal "json", result.signals["content_type"]
    assert_equal ["json_detected"], result.hints
  end

  test "json_post in internal mode persists native fetch metadata into distillator cache" do
    Distillator::FetchService.expects(:fetch_result).with do |kwargs|
      assert_equal :internal, kwargs[:mode]
      assert_equal true, kwargs[:scrape_options][:json_post]
      true
    end.returns(
      success_result(
        body: '{"ok":true}',
        headers: { content_type: "application/json" },
        signals: { network_status: "ok", content_type: "json", json_detected: true },
        hints: ["json_detected"],
        http_code: 200,
        final_url: "https://example.org/api/final",
        redirect_chain: ["https://example.org/api", "https://example.org/api/final"],
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(
      uri: "https://example.org/api",
      json_post: true,
      mode: :internal,
      force_scrape: true
    )
    cache = Distillator::FetchCache.find_by(uri_key: result.uri_key)

    assert_equal "native", result.fetch_path
    assert_equal 200, result.http_response_code
    assert_equal "https://example.org/api/final", result.final_url
    assert_equal ["https://example.org/api", "https://example.org/api/final"], result.redirect_chain
    assert_equal "json", result.signals["content_type"]
    assert_equal "POST", result.signals["request_method"]
    assert_equal "native", result.signals["fetch_backend"]
    assert_includes result.hints, "json_detected"
    assert_equal '{"ok":true}', cache.body
    assert_equal "json", cache.signals["content_type"]
  end

  test "json_post string false does not opt into post mode" do
    Distillator::FetchService.expects(:fetch_result).with do |kwargs|
      assert_equal false, kwargs[:scrape_options][:json_post]
      true
    end.returns(success_result(body: "<html>get mode</html>", fetch_path: "native"))

    result = Distillator::FetchCacheStore.fetch(
      uri: "https://example.org/api",
      json_post: "false",
      mode: :internal,
      force_scrape: true
    )

    assert_equal "<html>get mode</html>", result.html
  end

  test "json_post 404 preserves previous html body and successful_refresh" do
    old_successful_refresh = 2.hours.ago
    cache = create_cache(
      uri: "https://example.org/api",
      html: "<html>last good</html>",
      body: "<html>last good</html>",
      scrape_date: 2.days.ago,
      successful_refresh: old_successful_refresh
    )

    Distillator::FetchService.expects(:fetch_result).returns(
      abort_result(
        http_code: 404,
        raw_body: '{"error":"missing"}',
        headers: { content_type: "application/json" },
        signals: { network_status: "ok", content_type: "json", json_detected: true },
        hints: ["json_detected"],
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, json_post: true, force_scrape: true)

    assert_equal 404, result.http_response_code
    assert_equal "<html>last good</html>", result.html
    assert_equal "<html>last good</html>", result.body
    assert_equal old_successful_refresh.to_i, result.successful_refresh.to_i
    assert_equal "json", result.signals["content_type"]
  end

  test "json_post 500 preserves previous html body while updating status metadata" do
    old_successful_refresh = 2.hours.ago
    cache = create_cache(
      uri: "https://example.org/api",
      html: "<html>last good json post</html>",
      body: "<html>last good json post</html>",
      scrape_date: 2.days.ago,
      successful_refresh: old_successful_refresh
    )

    Distillator::FetchService.expects(:fetch_result).returns(
      abort_result(
        http_code: 500,
        raw_body: '{"error":"server"}',
        headers: { content_type: "application/json" },
        signals: { network_status: "ok", content_type: "json", json_detected: true, request_method: "POST" },
        hints: ["json_detected"],
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, json_post: true, force_scrape: true)

    assert_equal 500, result.http_response_code
    assert_equal "<html>last good json post</html>", result.html
    assert_equal "<html>last good json post</html>", result.body
    assert_equal old_successful_refresh.to_i, result.successful_refresh.to_i
    assert_equal "POST", result.signals["request_method"]
    assert_equal "json", result.signals["content_type"]
    assert_includes result.hints, "json_detected"
  end

  test "queue it issue preserves last good html while materializing issue metadata" do
    old_successful_refresh = 2.hours.ago
    cache = create_cache(
      uri: "https://example.org/events",
      html: "<html>last good event</html>",
      body: "<html>last good event</html>",
      scrape_date: 2.days.ago,
      successful_refresh: old_successful_refresh
    )

    Distillator::FetchService.expects(:fetch_result).returns(
      success_result(
        body: "<html>Queue-it Please wait while we redirect you</html>",
        headers: { content_type: "text/html" },
        signals: {
          network_status: "ok",
          content_type: "html",
          primary_issue_key: "queue_it",
          primary_issue_error_code: "system_queue",
          primary_issue_severity: "warning",
          primary_issue_category: "anti_bot",
          primary_issue_label: "Queue-it waiting room",
          primary_issue_delete: false
        },
        hints: ["system_queue", "queue_it", "waiting_room"],
        http_code: 200,
        fetch_path: "native"
      ).merge(
        wringer: {
          signals: {
            network_status: "ok",
            content_type: "html",
            primary_issue_key: "queue_it",
            primary_issue_error_code: "system_queue",
            primary_issue_severity: "warning",
            primary_issue_category: "anti_bot",
            primary_issue_label: "Queue-it waiting room",
            primary_issue_delete: false
          },
          hints: ["system_queue", "queue_it", "waiting_room"],
          policy_action: "abort_update"
        }
      )
    )

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape: true)
    cache.reload

    assert_equal "<html>last good event</html>", result.html
    assert_equal old_successful_refresh.to_i, result.successful_refresh.to_i
    assert_equal "queue_it", cache.primary_issue_key
    assert_equal "system_queue", cache.primary_issue_error_code
    assert_equal "Queue-it waiting room", cache.primary_issue_label
    assert_equal "warning", cache.primary_issue_severity
    assert_equal "anti_bot", cache.primary_issue_category
    assert_includes cache.issue_keys, "queue_it"
    assert_includes cache.issue_keys, "last_good_preserved_failure"
    assert_includes cache.issue_hints, "waiting_room"
    assert_equal false, cache.delete_candidate
  end

  test "render_js in internal mode persists rendered phantomjs metadata into distillator cache" do
    Distillator::FetchService.expects(:fetch_result).with do |kwargs|
      assert_equal true, kwargs[:render_js]
      assert_equal true, kwargs[:scrape_options][:use_phantomjs]
      assert_equal true, kwargs[:scrape_options][:iframe]
      true
    end.returns(
      success_result(
        body: "<html>rendered</html>",
        headers: { content_type: "text/html" },
        signals: { network_status: "ok", content_type: "html", renderer: "legacy_phantomjs" },
        hints: ["legacy_phantomjs"],
        http_code: 200,
        final_url: "https://example.org/rendered",
        redirect_chain: ["https://example.org/events", "https://example.org/rendered"],
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(
      uri: "https://example.org/eventsiframe",
      render_js: true,
      mode: :internal,
      force_scrape: true
    )
    cache = Distillator::FetchCache.find_by(uri_key: result.uri_key)

    assert_equal "native", result.fetch_path
    assert_equal "legacy_phantomjs", result.signals["renderer"]
    assert_equal "phantomjs", result.signals["fetch_backend"]
    assert_equal true, result.signals["use_phantomjs"]
    assert_equal true, result.signals["phantomjs_iframe_extraction"]
    assert_includes result.hints, "legacy_phantomjs"
    assert_equal "https://example.org/rendered", result.final_url
    assert_equal "<html>rendered</html>", cache.html
  end

  test "iframe url forces phantomjs even without explicit render_js or use_phantomjs" do
    Distillator::FetchService.expects(:fetch_result).with do |kwargs|
      assert_equal true, kwargs[:render_js]
      assert_equal true, kwargs[:scrape_options][:use_phantomjs]
      assert_equal true, kwargs[:scrape_options][:render_js]
      assert_equal true, kwargs[:scrape_options][:iframe]
      true
    end.returns(
      success_result(
        body: "<html>iframe child</html>",
        headers: { content_type: "text/html" },
        signals: {
          network_status: "ok",
          content_type: "html",
          renderer: "legacy_phantomjs",
          fetch_backend: "phantomjs",
          request_method: "GET",
          use_phantomjs: true,
          phantomjs_iframe_extraction: true
        },
        hints: ["legacy_phantomjs"],
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(
      uri: "https://example.org/eventsiframe",
      mode: :internal,
      force_scrape: true
    )

    assert_equal "<html>iframe child</html>", result.html
    assert_equal "phantomjs", result.signals["fetch_backend"]
    assert_equal true, result.signals["use_phantomjs"]
    assert_equal true, result.signals["phantomjs_iframe_extraction"]
  end

  test "phantomjs missing child frame failure preserves last good html and records hint" do
    cache = create_cache(
      uri: "https://example.org/eventsiframe",
      html: "<html>last good child frame</html>",
      body: "<html>last good child frame</html>",
      scrape_date: 2.days.ago,
      successful_refresh: 2.hours.ago,
      signals: { "network_status" => "ok", "content_type" => "html", "renderer" => "legacy_phantomjs" },
      hints: ["legacy_phantomjs"]
    )

    Distillator::FetchService.expects(:fetch_result).returns(
      {
        status: :abort,
        body: ["abort_update", { error_type: "PhantomjsIframeExtractionError" }],
        raw_body: nil,
        headers: { content_type: "application/json" },
        final_url: "https://example.org/eventsiframe",
        redirect_chain: [],
        wringer: {
          signals: {
            network_status: "ok",
            content_type: "json",
            renderer: "legacy_phantomjs",
            fetch_backend: "phantomjs",
            request_method: "GET",
            use_phantomjs: true,
            phantomjs_iframe_extraction: false
          },
          hints: ["legacy_phantomjs", "phantomjs_iframe_missing_child_content"]
        },
        http_code: nil,
        duration_ms: 8.0,
        fetch_path: "native"
      }
    )

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape: true)

    assert_equal "<html>last good child frame</html>", result.html
    assert_equal false, result.signals["phantomjs_iframe_extraction"]
    assert_includes result.hints, "phantomjs_iframe_missing_child_content"
  end

  test "use_phantomjs string false does not opt into rendered fetch" do
    Distillator::FetchService.expects(:fetch_result).with do |kwargs|
      assert_equal false, kwargs[:render_js]
      assert_equal false, kwargs[:scrape_options][:use_phantomjs]
      true
    end.returns(success_result(body: "<html>direct</html>", fetch_path: "native"))

    result = Distillator::FetchCacheStore.fetch(
      uri: "https://example.org/direct",
      use_phantomjs: "false",
      mode: :internal,
      force_scrape: true
    )

    assert_equal "<html>direct</html>", result.html
    assert_equal "native", result.fetch_path
  end

  test "rendered non 2xx preserves previous html while updating renderer metadata" do
    cache = create_cache(
      uri: "https://example.org/eventsiframe",
      html: "<html>last good rendered</html>",
      body: "<html>last good rendered</html>",
      scrape_date: 2.days.ago,
      successful_refresh: 2.hours.ago
    )

    Distillator::FetchService.expects(:fetch_result).returns(
      abort_result(
        http_code: 500,
        raw_body: '{"pageResponses":[]}',
        headers: { content_type: "application/json" },
        signals: { network_status: "ok", content_type: "json", renderer: "legacy_phantomjs" },
        hints: ["legacy_phantomjs"],
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, render_js: true, force_scrape: true)

    assert_equal 500, result.http_response_code
    assert_equal "<html>last good rendered</html>", result.html
    assert_equal "legacy_phantomjs", result.signals["renderer"]
    assert_equal "phantomjs", result.signals["fetch_backend"]
    assert_includes result.hints, "legacy_phantomjs"
    assert_includes result.hints, "last_good_preserved_failure"
  end

  test "phantomjs iframe extraction failure preserves last good html and records hint" do
    cache = create_cache(
      uri: "https://example.org/eventsiframe",
      html: "<html>last good iframe</html>",
      body: "<html>last good iframe</html>",
      scrape_date: 2.days.ago,
      successful_refresh: 2.hours.ago,
      signals: { "network_status" => "ok", "content_type" => "html", "renderer" => "legacy_phantomjs" },
      hints: ["legacy_phantomjs"]
    )

    Distillator::FetchService.expects(:fetch_result).returns(
      {
        status: :abort,
        body: ["abort_update", { error_type: "PhantomjsIframeExtractionError" }],
        raw_body: nil,
        headers: { content_type: "application/json" },
        final_url: "https://example.org/eventsiframe",
        redirect_chain: [],
        wringer: {
          signals: {
            network_status: "ok",
            content_type: "json",
            renderer: "legacy_phantomjs",
            fetch_backend: "phantomjs",
            request_method: "GET",
            use_phantomjs: true,
            phantomjs_iframe_extraction: false
          },
          hints: ["legacy_phantomjs", "phantomjs_iframe_malformed_json"]
        },
        http_code: nil,
        duration_ms: 8.0,
        fetch_path: "native"
      }
    )

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, render_js: true, force_scrape: true)

    assert_equal "<html>last good iframe</html>", result.html
    assert_equal false, result.signals["phantomjs_iframe_extraction"]
    assert_includes result.hints, "phantomjs_iframe_malformed_json"
  end

  test "2xx empty body preserves last good html while recording empty body metadata" do
    old_successful_refresh = 2.hours.ago
    cache = create_cache(
      uri: "https://example.org/empty",
      html: "<html>last good</html>",
      body: "<html>last good</html>",
      scrape_date: 2.days.ago,
      successful_refresh: old_successful_refresh
    )

    Distillator::FetchService.expects(:fetch_result).returns(
      success_result(
        body: "",
        headers: { content_type: "text/html" },
        signals: { network_status: "ok", content_type: "html", empty_body: true },
        hints: ["empty_body"],
        http_code: 200,
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape: true)

    assert_equal "<html>last good</html>", result.html
    assert_equal old_successful_refresh.to_i, result.successful_refresh.to_i
    assert_equal true, result.signals["empty_body"]
    assert_includes result.hints, "empty_body"
  end

  test "policy aborted 200 html records content rejection instead of empty body" do
    cache = create_cache(
      uri: "https://example.org/rejected",
      html: nil,
      body: nil,
      scrape_date: nil,
      successful_refresh: nil
    )

    Distillator::FetchService.expects(:fetch_result).returns(
      {
        status: :ok,
        body: "<html><body><h1>Une erreur est survenue</h1><p>Retry later.</p></body></html>",
        raw_body: "<html><body><h1>Une erreur est survenue</h1><p>Retry later.</p></body></html>",
        headers: { content_type: "text/html" },
        final_url: "https://example.org/rejected",
        redirect_chain: [],
        wringer: {
          policy_action: "abort_update",
          retry: true,
          cache: false,
          signals: {
            network_status: "ok",
            content_type: "html",
            primary_issue_key: "generic_error_text",
            primary_issue_label: "Generic error text observed",
            primary_issue_severity: "failed",
            primary_issue_match: {
              source: "body_text",
              pattern: "Une erreur est survenue",
              snippet: "Une erreur est survenue Retry later."
            }
          },
          hints: ["generic_error_text"]
        },
        http_code: 200,
        duration_ms: 3.0,
        fetch_path: "native"
      }
    )

    result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape: true)

    assert_nil result.html
    refute_equal true, result.signals["empty_body"]
    assert_equal true, result.signals["content_rejected"]
    assert_equal "abort_update", result.signals["storage_decision"]
    assert_equal "not_stored", result.signals["stored_body_state"]
    assert_equal "non_empty", result.signals["fetched_body_state"]
    assert_equal "generic_error_text", result.signals["primary_issue_key"]
    assert_equal "Une erreur est survenue", result.signals.dig("primary_issue_match", "pattern")
    assert_not_includes result.hints, "empty_body"
    assert_includes result.hints, "generic_error_text"
  end

  test "common failures preserve last good cache content" do
    old_successful_refresh = 2.hours.ago

    cases = [
      {
        name: "404",
        uri: "https://example.org/not-found",
        fetch_result: abort_result(
          http_code: 404,
          raw_body: "<html><title>Not Found</title></html>",
          headers: { content_type: "text/html" },
          signals: { network_status: "ok", content_type: "html" },
          hints: ["not_found"],
          fetch_path: "native"
        ),
        expected_signal_key: "content_success",
        expected_signal_value: false,
        expected_hint: "not_found"
      },
      {
        name: "500",
        uri: "https://example.org/server-error",
        fetch_result: abort_result(
          http_code: 500,
          raw_body: "<html><title>Server Error</title></html>",
          headers: { content_type: "text/html" },
          signals: { network_status: "ok", content_type: "html" },
          hints: ["http_server_error"],
          fetch_path: "native"
        ),
        expected_signal_key: "content_success",
        expected_signal_value: false,
        expected_hint: "http_server_error"
      },
      {
        name: "timeout",
        uri: "https://example.org/timeout-table",
        fetch_result: {
          status: :abort,
          body: ["abort_update", { error: "execution expired", error_type: "TimeoutError" }],
          raw_body: nil,
          headers: {},
          final_url: "https://example.org/timeout-table",
          redirect_chain: [],
          wringer: {
            signals: { network_status: "failed", timeout: true },
            hints: ["timeout"]
          },
          http_code: nil,
          duration_ms: 8.0,
          fetch_path: "native"
        },
        expected_signal_key: "timeout",
        expected_signal_value: true,
        expected_hint: "timeout"
      },
      {
        name: "blocked URL",
        uri: "http://example.org/blocked-table",
        fetch_result: {
          status: :abort,
          body: ["abort_update", { error: "Blocked localhost host: 127.0.0.1", error_type: "DistillatorFetchBlocked" }],
          raw_body: nil,
          headers: {},
          final_url: "http://example.org/blocked-table",
          redirect_chain: [],
          wringer: {
            signals: { network_status: "blocked", native_ineligible_reason: "blocked_url" },
            hints: ["blocked_url", "blocked"]
          },
          http_code: nil,
          duration_ms: 1.0,
          fetch_path: "blocked"
        },
        expected_signal_key: "native_ineligible_reason",
        expected_signal_value: "blocked_url",
        expected_hint: "blocked_url"
      },
      {
        name: "empty 2xx body",
        uri: "https://example.org/empty-table",
        fetch_result: success_result(
          body: "",
          headers: { content_type: "text/html" },
          signals: { network_status: "ok", content_type: "html", empty_body: true },
          hints: ["empty_body"],
          http_code: 200,
          fetch_path: "native"
        ),
        expected_signal_key: "empty_body",
        expected_signal_value: true,
        expected_hint: "empty_body"
      },
      {
        name: "HTTP 200 content failure",
        uri: "https://www.ovation.ca/event-table",
        fetch_result: {
          status: :ok,
          body: "<html><title>Recherche par titre</title></html>",
          raw_body: "<html><title>Recherche par titre</title></html>",
          headers: { content_type: "text/html" },
          final_url: "https://www.ovation.ca/Search/Title/",
          redirect_chain: ["https://www.ovation.ca/event-table", "https://www.ovation.ca/Search/Title/"],
          wringer: {
            policy_action: "abort_update",
            retry: false,
            cache: false,
            signals: {
              network_status: "ok",
              content_type: "html",
              primary_issue_key: "redirect_to_listing",
              blocking_issue_key: "redirect_to_listing",
              primary_issue_severity: "failed"
            },
            hints: ["redirect_to_listing"]
          },
          http_code: 200,
          duration_ms: 3.0,
          fetch_path: "native"
        },
        expected_signal_key: "blocking_issue_key",
        expected_signal_value: "redirect_to_listing",
        expected_hint: "redirect_to_listing"
      },
      {
        name: "unsupported control action",
        uri: "https://example.org/control-table",
        fetch_result: {
          status: :abort,
          body: ["unsupported_action", { error: "unsupported control action", error_type: "UnsupportedControlAction" }],
          raw_body: nil,
          headers: { content_type: "application/json" },
          final_url: "https://example.org/control-table",
          redirect_chain: [],
          wringer: {
            policy_action: "abort_update",
            signals: {
              network_status: "failed",
              control_action: "unsupported_action",
              blocking_issue_key: "unsupported_control_action"
            },
            hints: ["unsupported_control_action"]
          },
          http_code: nil,
          duration_ms: 2.0,
          fetch_path: "native"
        },
        expected_signal_key: "blocking_issue_key",
        expected_signal_value: "unsupported_control_action",
        expected_hint: "unsupported_control_action"
      },
      {
        name: "malformed abort/control payload",
        uri: "https://example.org/malformed-table",
        fetch_result: {
          status: :abort,
          body: ["abort_update", "malformed"],
          raw_body: nil,
          headers: { content_type: "application/json" },
          final_url: "https://example.org/malformed-table",
          redirect_chain: [],
          wringer: {
            signals: {
              network_status: "failed",
              blocking_issue_key: "malformed_control_payload"
            },
            hints: ["malformed_control_payload"]
          },
          http_code: nil,
          duration_ms: 2.0,
          fetch_path: "native"
        },
        expected_signal_key: "blocking_issue_key",
        expected_signal_value: "malformed_control_payload",
        expected_hint: "malformed_control_payload"
      }
    ]

    cases.each do |test_case|
      cache = create_cache(
        uri: test_case[:uri],
        html: "<html>last good #{test_case[:name]}</html>",
        body: "<html>last good #{test_case[:name]}</html>",
        scrape_date: 2.days.ago,
        successful_refresh: old_successful_refresh
      )
      old_scrape_date = cache.scrape_date

      Distillator::FetchService.expects(:fetch_result).returns(test_case[:fetch_result])

      result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, force_scrape: true)
      cache.reload

      assert_equal "<html>last good #{test_case[:name]}</html>", result.html, test_case[:name]
      assert_equal "<html>last good #{test_case[:name]}</html>", result.body, test_case[:name]
      assert_equal "<html>last good #{test_case[:name]}</html>", cache.html, test_case[:name]
      assert_equal "<html>last good #{test_case[:name]}</html>", cache.body, test_case[:name]
      assert_equal old_successful_refresh.to_i, result.successful_refresh.to_i, test_case[:name]
      assert_equal old_successful_refresh.to_i, cache.successful_refresh.to_i, test_case[:name]
      assert_operator result.scrape_date, :>, old_scrape_date, test_case[:name]
      assert_operator cache.scrape_date, :>, old_scrape_date, test_case[:name]
      assert_equal true, result.signals["last_good_preserved_failure"], test_case[:name]
      assert_equal true, cache.signals["last_good_preserved_failure"], test_case[:name]
      assert_includes result.hints, "last_good_preserved_failure", test_case[:name]
      assert_includes cache.hints, "last_good_preserved_failure", test_case[:name]
      assert_equal test_case[:expected_signal_value], result.signals[test_case[:expected_signal_key]], test_case[:name]
      assert_equal test_case[:expected_signal_value], cache.signals[test_case[:expected_signal_key]], test_case[:name]
      assert_includes result.hints, test_case[:expected_hint], test_case[:name]
      assert_includes cache.hints, test_case[:expected_hint], test_case[:name]
    end
  end

  test "all failed fetch paths preserve last good content and record latest attempt metadata" do
    old_successful_refresh = 2.hours.ago

    cases = [
      {
        name: "normal get transport failure",
        uri: "https://example.org/timeout",
        fetch_options: { force_scrape: true },
        fetch_result: {
          status: :abort,
          body: ["abort_update", { error: "execution expired", error_type: "TimeoutError" }],
          raw_body: nil,
          headers: {},
          final_url: "https://example.org/timeout",
          redirect_chain: [],
          wringer: {
            signals: { network_status: "failed", timeout: true },
            hints: ["timeout"]
          },
          http_code: nil,
          duration_ms: 8.0,
          fetch_path: "native"
        },
        expected_signal_key: "timeout",
        expected_signal_value: true,
        expected_hint: "timeout"
      },
      {
        name: "normal get non 2xx",
        uri: "https://example.org/server-error",
        fetch_options: { force_scrape: true },
        fetch_result: abort_result(
          http_code: 500,
          raw_body: "<html><title>Server Error</title></html>",
          headers: { content_type: "text/html" },
          signals: { network_status: "ok", content_type: "html" },
          hints: ["http_server_error"],
          fetch_path: "native"
        ),
        expected_signal_key: "content_type",
        expected_signal_value: "html",
        expected_hint: "http_server_error"
      },
      {
        name: "rendered failure",
        uri: "https://example.org/eventsiframe",
        fetch_options: { force_scrape: true, render_js: true },
        fetch_result: abort_result(
          http_code: 500,
          raw_body: "{\"pageResponses\":[]}",
          headers: { content_type: "application/json" },
          signals: { network_status: "ok", content_type: "json", renderer: "legacy_phantomjs" },
          hints: ["legacy_phantomjs"],
          fetch_path: "native"
        ),
        expected_signal_key: "renderer",
        expected_signal_value: "legacy_phantomjs",
        expected_hint: "legacy_phantomjs"
      },
      {
        name: "post failure",
        uri: "https://example.org/api",
        fetch_options: { force_scrape: true, json_post: true },
        fetch_result: abort_result(
          http_code: 500,
          raw_body: "{\"error\":\"server\"}",
          headers: { content_type: "application/json" },
          signals: { network_status: "ok", content_type: "json", request_method: "POST" },
          hints: ["json_detected"],
          fetch_path: "native"
        ),
        expected_signal_key: "request_method",
        expected_signal_value: "POST",
        expected_hint: "json_detected"
      },
      {
        name: "blocked url",
        uri: "http://example.org/blocked",
        fetch_options: { force_scrape: true },
        fetch_result: {
          status: :abort,
          body: ["abort_update", { error: "Blocked localhost host: 127.0.0.1", error_type: "DistillatorFetchBlocked" }],
          raw_body: nil,
          headers: {},
          final_url: "http://example.org/blocked",
          redirect_chain: [],
          wringer: {
            signals: { network_status: "blocked", native_ineligible_reason: "blocked_url" },
            hints: ["blocked_url", "blocked"]
          },
          http_code: nil,
          duration_ms: 1.0,
          fetch_path: "blocked"
        },
        expected_signal_key: "native_ineligible_reason",
        expected_signal_value: "blocked_url",
        expected_hint: "blocked"
      },
      {
        name: "content failure",
        uri: "https://www.ovation.ca/event",
        fetch_options: { force_scrape: true },
        fetch_result: {
          status: :ok,
          body: "<html><title>Recherche par titre</title></html>",
          raw_body: "<html><title>Recherche par titre</title></html>",
          headers: { content_type: "text/html" },
          final_url: "https://www.ovation.ca/Search/Title/",
          redirect_chain: ["https://www.ovation.ca/event", "https://www.ovation.ca/Search/Title/"],
          wringer: {
            policy_action: "abort_update",
            retry: false,
            cache: false,
            signals: {
              network_status: "ok",
              content_type: "html",
              primary_issue_key: "redirect_to_listing",
              blocking_issue_key: "redirect_to_listing",
              primary_issue_severity: "failed"
            },
            hints: ["redirect_to_listing"]
          },
          http_code: 200,
          duration_ms: 3.0,
          fetch_path: "native"
        },
        expected_signal_key: "blocking_issue_key",
        expected_signal_value: "redirect_to_listing",
        expected_hint: "redirect_to_listing"
      },
      {
        name: "unsafe redirect",
        uri: "https://example.org/unsafe-redirect",
        fetch_options: { force_scrape: true },
        fetch_result: {
          status: :abort,
          body: ["abort_update", { error: "Blocked localhost host: 127.0.0.1", error_type: "DistillatorFetchBlocked" }],
          raw_body: nil,
          headers: {},
          final_url: "http://127.0.0.1/private",
          redirect_chain: ["https://example.org/unsafe-redirect", "http://127.0.0.1/private"],
          wringer: {
            signals: {
              network_status: "blocked",
              native_ineligible_reason: "blocked_url",
              redirect_type: "unsafe"
            },
            hints: ["blocked_url", "blocked"]
          },
          http_code: nil,
          duration_ms: 2.0,
          fetch_path: "blocked"
        },
        expected_signal_key: "native_ineligible_reason",
        expected_signal_value: "blocked_url",
        expected_hint: "blocked"
      },
      {
        name: "ssl failure",
        uri: "https://example.org/ssl-failure",
        fetch_options: { force_scrape: true },
        fetch_result: {
          status: :abort,
          body: ["abort_update", { error: "certificate verify failed", error_type: "SSLFailure" }],
          raw_body: nil,
          headers: {},
          final_url: "https://example.org/ssl-failure",
          redirect_chain: [],
          wringer: {
            signals: {
              network_status: "failed",
              system_error: true,
              blocking_issue_key: "ssl_error"
            },
            hints: ["ssl_error"]
          },
          http_code: nil,
          duration_ms: 2.0,
          fetch_path: "native"
        },
        expected_signal_key: "blocking_issue_key",
        expected_signal_value: "ssl_error",
        expected_hint: "ssl_error"
      },
      {
        name: "unsupported control action",
        uri: "https://example.org/control",
        fetch_options: { force_scrape: true },
        fetch_result: {
          status: :abort,
          body: ["unsupported_action", { error: "unsupported control action", error_type: "UnsupportedControlAction" }],
          raw_body: nil,
          headers: { content_type: "application/json" },
          final_url: "https://example.org/control",
          redirect_chain: [],
          wringer: {
            policy_action: "abort_update",
            signals: {
              network_status: "failed",
              control_action: "unsupported_action",
              blocking_issue_key: "unsupported_control_action"
            },
            hints: ["unsupported_control_action"]
          },
          http_code: nil,
          duration_ms: 2.0,
          fetch_path: "native"
        },
        expected_signal_key: "blocking_issue_key",
        expected_signal_value: "unsupported_control_action",
        expected_hint: "unsupported_control_action"
      },
      {
        name: "redirect without valid success",
        uri: "https://example.org/redirect",
        fetch_options: { force_scrape: true },
        fetch_result: {
          status: :abort,
          body: ["abort_update", { error: "redirect without final success", error_type: "RedirectFailure" }],
          raw_body: "<html>moved</html>",
          headers: { content_type: "text/html" },
          final_url: "https://example.org/moved",
          redirect_chain: ["https://example.org/redirect", "https://example.org/moved"],
          wringer: {
            signals: {
              network_status: "ok",
              content_type: "html",
              redirect_type: "normal",
              blocking_issue_key: "redirect_failed"
            },
            hints: ["redirect_failed"]
          },
          http_code: 302,
          duration_ms: 2.0,
          fetch_path: "native"
        },
        expected_signal_key: "blocking_issue_key",
        expected_signal_value: "redirect_failed",
        expected_hint: "redirect_failed"
      },
      {
        name: "malformed control payload",
        uri: "https://example.org/malformed",
        fetch_options: { force_scrape: true },
        fetch_result: {
          status: :abort,
          body: ["abort_update", "malformed"],
          raw_body: nil,
          headers: { content_type: "application/json" },
          final_url: "https://example.org/malformed",
          redirect_chain: [],
          wringer: {
            signals: {
              network_status: "failed",
              blocking_issue_key: "malformed_control_payload"
            },
            hints: ["malformed_control_payload"]
          },
          http_code: nil,
          duration_ms: 2.0,
          fetch_path: "native"
        },
        expected_signal_key: "blocking_issue_key",
        expected_signal_value: "malformed_control_payload",
        expected_hint: "malformed_control_payload"
      }
    ]

    cases.each do |test_case|
      cache = create_cache(
        uri: test_case[:uri],
        html: "<html>last good #{test_case[:name]}</html>",
        body: "<html>last good #{test_case[:name]}</html>",
        scrape_date: 2.days.ago,
        successful_refresh: old_successful_refresh
      )
      old_scrape_date = cache.scrape_date

      Distillator::FetchService.expects(:fetch_result).returns(test_case[:fetch_result])

      result = Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, **test_case[:fetch_options])
      cache.reload

      assert_equal "<html>last good #{test_case[:name]}</html>", result.html, test_case[:name]
      assert_equal "<html>last good #{test_case[:name]}</html>", result.body, test_case[:name]
      assert_equal "<html>last good #{test_case[:name]}</html>", cache.html, test_case[:name]
      assert_equal "<html>last good #{test_case[:name]}</html>", cache.body, test_case[:name]
      assert_equal old_successful_refresh.to_i, result.successful_refresh.to_i, test_case[:name]
      assert_equal old_successful_refresh.to_i, cache.successful_refresh.to_i, test_case[:name]
      assert_operator result.scrape_date, :>, old_scrape_date, test_case[:name]
      assert_operator cache.scrape_date, :>, old_scrape_date, test_case[:name]
      assert_equal true, result.signals["last_good_preserved_failure"], test_case[:name]
      assert_equal true, cache.signals["last_good_preserved_failure"], test_case[:name]
      assert_includes result.hints, "last_good_preserved_failure", test_case[:name]
      assert_includes cache.hints, "last_good_preserved_failure", test_case[:name]
      assert_equal test_case[:expected_signal_value], result.signals[test_case[:expected_signal_key]], test_case[:name]
      assert_equal test_case[:expected_signal_value], cache.signals[test_case[:expected_signal_key]], test_case[:name]
      assert_includes result.hints, test_case[:expected_hint], test_case[:name]
      assert_includes cache.hints, test_case[:expected_hint], test_case[:name]
    end
  end

  test "successful direct get escapes erb tokens before cache write" do
    body = "<html><body><% dangerous %></body></html>"
    Distillator::FetchService.expects(:fetch_result).returns(
      success_result(
        body: body,
        final_url: "https://example.org/template",
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(
      uri: "https://example.org/template",
      force_scrape: true
    )

    assert_equal "<html><body><&percnt; dangerous &percnt;></body></html>", result.html
  end

  test "absolute_src true rewrites cached html via html rewriter" do
    Distillator::FetchService.expects(:fetch_result).returns(
      success_result(
        body: '<img src="/image.png"><a href="events/opening-night">opening night</a>',
        final_url: "https://example.org/artist/",
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(
      uri: "https://example.org/artist/",
      absolute_src: true,
      force_scrape: true
    )

    assert_includes result.html, 'src="https://example.org/image.png"'
    assert_includes result.html, 'href="https://example.org/artist/events/opening-night"'
  end

  test "absolute_src false leaves cached body untouched" do
    body = '<img src="/image.png"><a href="events/opening-night">opening night</a>'
    Distillator::FetchService.expects(:fetch_result).returns(
      success_result(
        body: body,
        final_url: "https://example.org/artist/",
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(
      uri: "https://example.org/artist/",
      absolute_src: false,
      force_scrape: true
    )

    assert_equal body, result.body
    assert_equal body, result.html
  end

  test "absolute_src string false leaves cached body untouched" do
    body = '<img src="/image.png"><a href="events/opening-night">opening night</a>'
    Distillator::FetchService.expects(:fetch_result).returns(
      success_result(
        body: body,
        final_url: "https://example.org/artist/",
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(
      uri: "https://example.org/artist/",
      absolute_src: "false",
      force_scrape: true
    )

    assert_equal body, result.body
    assert_equal body, result.html
  end

  test "absolute_src true preserves malformed src while rewriting valid relative links" do
    body = '<img src="not a path" width="100px"><a href="/path">path</a>'
    Distillator::FetchService.expects(:fetch_result).returns(
      success_result(
        body: body,
        final_url: "https://example.org/artist/",
        fetch_path: "native"
      )
    )

    result = Distillator::FetchCacheStore.fetch(
      uri: "https://example.org/artist/",
      absolute_src: true,
      force_scrape: true
    )

    assert_includes result.html, 'src="not a path"'
    assert_includes result.html, 'href="https://example.org/path"'
    assert_includes result.html, 'width="100px"'
  end

  test "abort fetch without a successful cached body returns structured abort payload" do
    Distillator::FetchService.expects(:fetch_result).returns(
      {
        status: :abort,
        body: ["abort_update", { error: "connection reset", error_type: "NativeFetchError", source: "native_fetch", retry: true, cache: false }],
        raw_body: nil,
        headers: {},
        final_url: "http://example.org/failure",
        redirect_chain: [],
        wringer: {
          error_type: "NativeFetchError",
          source: "native_fetch",
          retry: true,
          cache: false,
          signals: { network_status: "failed" },
          hints: ["timeout"]
        },
        http_code: nil,
        duration_ms: 4.0,
        fetch_path: "native"
      }
    )

    result = Distillator::FetchCacheStore.fetch(uri: "http://example.org/failure", force_scrape: true)

    assert_equal :abort, result.status
    assert_equal "abort_update", result.body.first
    assert_equal "NativeFetchError", result.body.last[:error_type]
    assert_equal "failed", result.signals["network_status"]
    assert_equal ["timeout"], result.hints
    assert_equal "native", result.fetch_path
  end

  test "blocked native fetch without cached body returns structured blocked abort payload" do
    Distillator::FetchService.expects(:fetch_result).returns(
      {
        status: :abort,
        body: ["abort_update", { error: "Blocked localhost host: 127.0.0.1", error_type: "DistillatorFetchBlocked", source: "distillator_fetch_guard", retry: false, cache: false, step: "url" }],
        raw_body: nil,
        headers: {},
        final_url: "http://127.0.0.1/events",
        redirect_chain: [],
        wringer: {
          error_type: "DistillatorFetchBlocked",
          source: "distillator_fetch_guard",
          retry: false,
          cache: false,
          signals: { network_status: "blocked", native_ineligible_reason: "blocked_url" },
          hints: ["blocked_url", "blocked"]
        },
        http_code: nil,
        duration_ms: 1.0,
        fetch_path: "blocked"
      }
    )

    result = Distillator::FetchCacheStore.fetch(uri: "http://127.0.0.1/events", force_scrape: true)

    assert_equal :abort, result.status
    assert_equal "abort_update", result.body.first
    assert_equal "DistillatorFetchBlocked", result.body.last[:error_type]
    assert_equal "blocked", result.signals["network_status"]
    assert_equal "blocked_url", result.signals["native_ineligible_reason"]
    assert_equal ["blocked_url", "blocked"], result.hints
    assert_equal "blocked", result.fetch_path
  end

  test "blocked url does not overwrite last good cache content or perform a network fetch" do
    old_successful_refresh = 5.hours.ago
    cache = create_cache(
      uri: "http://127.0.0.1/events",
      html: "<html>last good blocked</html>",
      body: "<html>last good blocked</html>",
      scrape_date: 2.days.ago,
      successful_refresh: old_successful_refresh
    )
    old_scrape_date = cache.scrape_date

    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never

    result = Distillator::FetchCacheStore.fetch(
      uri: cache.normalized_url,
      mode: :internal,
      force_scrape: true
    )
    cache.reload

    assert_equal "<html>last good blocked</html>", result.html
    assert_equal "<html>last good blocked</html>", result.body
    assert_equal "<html>last good blocked</html>", cache.html
    assert_equal "<html>last good blocked</html>", cache.body
    assert_equal old_successful_refresh.to_i, result.successful_refresh.to_i
    assert_equal old_successful_refresh.to_i, cache.successful_refresh.to_i
    assert_operator result.scrape_date, :>, old_scrape_date
    assert_operator cache.scrape_date, :>, old_scrape_date
    assert_equal "blocked", result.signals["network_status"]
    assert_equal "blocked_url", result.signals["native_ineligible_reason"]
    assert_equal true, result.signals["last_good_preserved_failure"]
    assert_includes result.hints, "blocked_url"
    assert_includes result.hints, "blocked"
    assert_includes result.hints, "last_good_preserved_failure"
  end

  private

  def create_cache(uri: "http://example.org/cached", html: "<html>cached</html>", body: html, name: "Cached", scrape_date:, successful_refresh:, http_response_code: 200, headers: {}, signals: { "network_status" => "ok", "content_type" => "html" }, hints: [], final_url: nil, redirect_chain: [])
    key = Distillator::WringerUrlKey.call(uri)

    Distillator::FetchCache.create!(
      uri_key: key.uri_key,
      normalized_url: key.normalized_url,
      html: html,
      body: body,
      name: name,
      scrape_date: scrape_date,
      successful_refresh: successful_refresh,
      http_response_code: http_response_code,
      headers: headers,
      signals: signals,
      hints: hints,
      final_url: final_url,
      redirect_chain: redirect_chain
    )
  end

  def success_result(body:, headers: { content_type: "text/html" }, signals: { network_status: "ok", content_type: "html" }, hints: [], http_code: 200, final_url: nil, redirect_chain: nil, fetch_path: "native")
    {
      status: :ok,
      body: body,
      raw_body: body,
      headers: headers,
      final_url: final_url,
      redirect_chain: redirect_chain || Array(final_url).compact,
      wringer: {
        signals: signals,
        hints: hints
      },
      http_code: http_code,
      duration_ms: 12.5,
      fetch_path: fetch_path
    }
  end

  def abort_result(http_code:, raw_body:, headers:, signals:, hints:, fetch_path:)
    {
      status: :abort,
      body: ["abort_update", { error_type: "http_server_error" }],
      raw_body: raw_body,
      headers: headers,
      final_url: "http://example.org/cached",
      redirect_chain: [],
      wringer: {
        signals: signals,
        hints: hints,
        http_code: http_code
      },
      http_code: http_code,
      duration_ms: 8.0,
      fetch_path: fetch_path
    }
  end
end
