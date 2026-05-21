# frozen_string_literal: true

require "test_helper"

# Tests for Distillator::CacheHealthMaterializer.
#
# These tests protect the save-time materialization layer used by the cache
# operations UI. The materializer turns a FetchCache row's raw cache state into
# queryable health and issue fields.
#
# Runtime chain under test:
#
#   Distillator::FetchCache
#     -> before_save
#     -> Distillator::CacheHealthMaterializer.call(cache)
#     -> Distillator::CacheHealth.call(cache)
#     -> Distillator::WringerIssueSet.call(...)
#     -> config/wringer.yml
#     -> materialized FetchCache fields
#
# Important behaviors:
# - health fields are derived from cache status;
# - byte counts are materialized for blob-free index/summary pages;
# - issue labels/severity/category are resolved from config/wringer.yml;
# - issue keys/hints are queryable without reparsing cache HTML/body;
# - when last-good content is preserved after a failed refresh, stale body text
#   must not become the primary issue.
#
class Distillator::CacheHealthMaterializerTest < ActiveSupport::TestCase
  test "materializes health status sizes signals and hints" do
    cache = build_cache(
      uri: "http://example.org/json",
      html: "<html>cached</html>",
      body: '{"ok":true}',
      scrape_date: Time.zone.now,
      successful_refresh: Time.zone.now,
      http_response_code: 200,
      signals: { "network_status" => "ok", "content_type" => "json" },
      hints: ["json_detected"],
      final_url: "https://example.org/json",
      redirect_chain: ["http://example.org/json", "https://example.org/json"]
    )

    Distillator::CacheHealthMaterializer.call(cache)

    assert_equal "healthy", cache.health_status
    assert_equal "ok", cache.health_severity
    assert_equal ["successful_2xx_refresh"], cache.health_reasons
    assert_equal "<html>cached</html>".bytesize, cache.html_bytes
    assert_equal '{"ok":true}'.bytesize, cache.body_bytes
    assert_equal true, cache.redirected
    assert_equal "ok", cache.network_status
    assert_equal "json", cache.content_type
    assert_equal ["json_detected"], cache.hint_keys
  end

  test "materializes primary issue fields from signals and yaml metadata" do
    cache = build_cache(
      uri: "http://example.org/queue",
      html: "<html>cached</html>",
      body: "<html>cached</html>",
      scrape_date: Time.zone.now,
      successful_refresh: 1.day.ago,
      http_response_code: 200,
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "primary_issue_key" => "queue_it",
        "primary_issue_error_code" => "system_queue",
        "primary_issue_delete" => false
      },
      hints: ["queue_it"],
      final_url: "http://example.org/queue"
    )

    Distillator::CacheHealthMaterializer.call(cache)

    assert_equal "queue_it", cache.primary_issue_key
    assert_equal "system_queue", cache.primary_issue_error_code
    assert_equal "Queue-it waiting room", cache.primary_issue_label
    assert_equal "warning", cache.primary_issue_severity
    assert_equal "anti_bot", cache.primary_issue_category
    assert_equal ["queue_it"], cache.issue_keys
    assert_includes cache.issue_hints, "waiting_room"
    assert_equal false, cache.delete_candidate
  end

  test "materializes issue fields from latest failure metadata when last good body is preserved" do
    cache = build_cache(
      uri: "http://example.org/timeout",
      html: "<html>last good</html>",
      body: "<html>last good</html>",
      scrape_date: Time.zone.now,
      successful_refresh: 1.hour.ago,
      http_response_code: 500,
      signals: {
        "network_status" => "failed",
        "content_type" => "html",
        "primary_issue_key" => "timeout",
        "primary_issue_error_code" => "timeout",
        "primary_issue_severity" => "failed",
        "primary_issue_category" => "network",
        "primary_issue_label" => "Fetch timeout",
        "primary_issue_delete" => false,
        "last_good_preserved_failure" => true
      },
      hints: %w[timeout last_good_preserved_failure],
      final_url: "http://example.org/timeout"
    )

    Distillator::CacheHealthMaterializer.call(cache)

    assert_equal "timeout", cache.primary_issue_key
    assert_includes cache.issue_keys, "timeout"
    assert_includes cache.issue_keys, "http_5xx"
    assert_includes cache.issue_hints, "timeout"
    assert_equal false, cache.delete_candidate
  end

  test "last good preserved timeout is not overridden by stale error text in cached body" do
    cache = build_cache(
      uri: "http://example.org/stale-error-body",
      html: "<html>Error from old cached page</html>",
      body: "<html>Error from old cached page</html>",
      scrape_date: Time.zone.now,
      successful_refresh: 1.hour.ago,
      http_response_code: nil,
      signals: {
        "network_status" => "failed",
        "content_type" => "html",
        "primary_issue_key" => "timeout",
        "primary_issue_error_code" => "timeout",
        "primary_issue_severity" => "failed",
        "primary_issue_category" => "network",
        "primary_issue_label" => "Fetch timeout",
        "last_good_preserved_failure" => true
      },
      hints: %w[timeout last_good_preserved_failure],
      final_url: "http://example.org/stale-error-body"
    )

    Distillator::CacheHealthMaterializer.call(cache)

    assert_equal "timeout", cache.primary_issue_key
    assert_equal "timeout", cache.primary_issue_error_code
    assert_equal "network", cache.primary_issue_category
    assert_includes cache.issue_keys, "timeout"
    assert_not_includes cache.issue_keys, "generic_error_text"
  end

  test "last good preserved http 5xx is not overridden by stale POST call text in cached body" do
    cache = build_cache(
      uri: "http://example.org/stale-post-call-body",
      html: "<html>POST call from old cached page</html>",
      body: "<html>POST call from old cached page</html>",
      scrape_date: Time.zone.now,
      successful_refresh: 1.hour.ago,
      http_response_code: 500,
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "last_good_preserved_failure" => true
      },
      hints: ["last_good_preserved_failure"],
      final_url: "http://example.org/stale-post-call-body"
    )

    Distillator::CacheHealthMaterializer.call(cache)

    assert_equal "http_5xx", cache.primary_issue_key
    assert_equal "http_server_error", cache.primary_issue_error_code
    assert_equal "http", cache.primary_issue_category
    assert_includes cache.issue_keys, "http_5xx"
    assert_not_includes cache.issue_keys, "post_call_observed"
  end

  test "body text can still classify issue when last good content is not preserved" do
    cache = build_cache(
      uri: "http://example.org/queue-body",
      html: "<html>Queue-it Please wait while we redirect you</html>",
      body: "<html>Queue-it Please wait while we redirect you</html>",
      scrape_date: Time.zone.now,
      successful_refresh: nil,
      http_response_code: 200,
      signals: {
        "network_status" => "ok",
        "content_type" => "html"
      },
      hints: [],
      final_url: "http://example.org/queue-body"
    )

    Distillator::CacheHealthMaterializer.call(cache)

    assert_equal "queue_it", cache.primary_issue_key
    assert_equal "system_queue", cache.primary_issue_error_code
    assert_equal "anti_bot", cache.primary_issue_category
    assert_includes cache.issue_keys, "queue_it"
  end

  test "failed redirect listing attempt is materialized as attempt failed instead of never fetched" do
    cache = build_cache(
      uri: "https://www.ovation.ca/event",
      html: nil,
      body: nil,
      scrape_date: Time.zone.now,
      successful_refresh: nil,
      http_response_code: 200,
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "renderer" => "legacy_phantomjs",
        "renderer_unavailable" => true,
        "renderer_fallback" => "direct_url",
        "primary_issue_key" => "redirect_to_listing",
        "primary_issue_severity" => "failed",
        "content_success" => false
      },
      hints: %w[legacy_phantomjs phantomjs_unavailable redirect_to_listing],
      final_url: "https://www.ovation.ca/Search/Title/",
      redirect_chain: ["https://www.ovation.ca/event", "https://www.ovation.ca/Search/Title/"]
    )

    Distillator::CacheHealthMaterializer.call(cache)

    assert_equal "attempt_failed", cache.health_status
    assert_equal "redirect_to_listing", cache.primary_issue_key
  end

  test "policy aborted non empty html materializes as content rejected instead of empty body" do
    cache = build_cache(
      uri: "https://example.org/rejected",
      html: nil,
      body: nil,
      scrape_date: Time.zone.now,
      successful_refresh: nil,
      http_response_code: 200,
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "transport_success" => true,
        "content_success" => false,
        "policy_action" => "abort_update",
        "content_rejected" => true,
        "fetched_body_state" => "non_empty",
        "fetched_body_bytes" => 96,
        "stored_body_state" => "not_stored",
        "storage_decision" => "abort_update",
        "cache_body_empty_after_abort" => true,
        "primary_issue_key" => "generic_error_text",
        "primary_issue_label" => "Generic error text observed",
        "primary_issue_severity" => "failed",
        "primary_issue_match" => {
          "source" => "body_text",
          "pattern" => "Une erreur est survenue",
          "snippet" => "Une erreur est survenue Retry later."
        }
      },
      hints: ["generic_error_text"],
      final_url: "https://example.org/rejected"
    )

    Distillator::CacheHealthMaterializer.call(cache)

    assert_equal "content_rejected", cache.health_status
    assert_equal "high", cache.health_severity
    assert_equal "generic_error_text", cache.primary_issue_key
    assert_equal "Generic error text observed", cache.primary_issue_label
    refute_includes cache.health_reasons, "empty_body"
  end

  private

  # Build an unsaved FetchCache with realistic defaults.
  #
  # The materializer mutates the object in memory, so these tests do not need to
  # persist rows unless they are explicitly testing callbacks or database indexes.
  def build_cache(
    uri:,
    html: nil,
    body: nil,
    scrape_date: nil,
    successful_refresh: nil,
    http_response_code: nil,
    headers: {},
    signals: {},
    hints: [],
    final_url: nil,
    redirect_chain: []
  )
    Distillator::FetchCache.new(
      uri_key: CGI.escape(uri),
      normalized_url: uri,
      html: html,
      body: body,
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
end
