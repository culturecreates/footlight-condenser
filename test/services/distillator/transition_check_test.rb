require "test_helper"

class Distillator::TransitionCheckTest < ActiveSupport::TestCase
  test "blocked cache health makes promotable false" do
    website = build_website("blocked-transition-check")
    cache = build_cache(
      website: website,
      url: "https://blocked-transition-check.example/event",
      signals: { "transport_success" => false, "content_success" => false },
      health_status: "attempt_failed"
    )

    result = Distillator::TransitionCheck.call(website: website, cache: cache)

    assert_equal website.id, result.website_id
    assert_equal :shadow, result.mode
    assert_equal false, result.promotable
    assert_equal :wringer, result.active_backend
    assert_equal cache.reload.health_status.to_s.presence || "unknown", result.latest_cache_status
    assert_equal true, result.cache_present
    assert result.blocking_issues.any?
  end

  test "healthy shadow cache with representative checks makes promotable true" do
    website = build_website("ready-transition-check")
    url = "https://ready-transition-check.example/event"
    cache = build_cache(
      website: website,
      url: url,
      signals: { "transport_success" => true, "content_success" => true }
    )
    website.transition_evidences.create!(url: url, check_kind: "statement_delta", status: "checked", statement_count_delta_acceptable: true, checked_at: 1.hour.ago)
    website.transition_evidences.create!(url: url, check_kind: "export_diff", status: "checked", export_diff_checked: true, checked_at: 1.hour.ago)

    result = Distillator::TransitionCheck.call(website: website, cache: cache)

    assert_equal :ready, result.status
    assert_equal true, result.promotable
    assert_equal :passed, result.fetch
    assert_equal :passed, result.statements
    assert_equal :passed, result.export
    assert_equal true, result.compare_available
  end

  test "la vitrine site does not become promotable from cache health alone" do
    website = build_website("hector-charland-com")
    cache = build_cache(
      website: website,
      url: "https://hector-charland-com.example/event",
      signals: { "transport_success" => true, "content_success" => true },
      health_status: "healthy"
    )

    result = Distillator::TransitionCheck.call(website: website, cache: cache)

    assert_equal :blocked, result.status
    assert_equal false, result.promotable
    assert_includes result.blocking_issues, "Cannot activate yet: statements check is missing."
  end

  test "run fetch forces internal condenser evidence before compare and uses the fresh cache" do
    website = build_website("forced-fetch-transition-check")
    stale_cache = build_cache(
      website: website,
      url: "https://forced-fetch-transition-check.example/event",
      signals: { "transport_success" => false, "content_success" => false, "empty_body" => true },
      health_status: "empty_body"
    )
    fresh_cache = stale_cache.dup
    fresh_cache.assign_attributes(
      html: "<html>fresh</html>",
      body: "<html>fresh</html>",
      scrape_date: Time.current,
      successful_refresh: Time.current,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: stale_cache.normalized_url,
      health_status: "healthy"
    )
    fetch_result = Distillator::FetchCacheStore::Result.new(
      status: :ok,
      body: "<html>fresh</html>",
      html: "<html>fresh</html>",
      headers: {},
      final_url: stale_cache.normalized_url,
      redirect_chain: [],
      http_response_code: 200,
      signals: { "transport_success" => true, "content_success" => true },
      hints: [],
      duration_ms: 10,
      cache_hit: false,
      cache_write: true,
      cache_reason: "force_scrape",
      uri_key: stale_cache.uri_key,
      normalized_url: stale_cache.normalized_url,
      fetch_path: "native",
      name: "fresh",
      scrape_date: Time.current,
      successful_refresh: Time.current,
      cache: fresh_cache
    )
    fetch_cache_store = mock
    fetch_cache_store.expects(:fetch).with do |kwargs|
      assert_equal stale_cache.normalized_url, kwargs[:uri]
      assert_equal true, kwargs[:force_scrape]
      assert_equal "internal", kwargs[:mode]
      assert_equal website, kwargs[:website]
      assert_equal "transition_check", kwargs.dig(:log_context, :source)
      true
    end.returns(fetch_result)
    comparison = {
      summary: { promotable: true, blocking_regressions: [] },
      missing: { legacy: false, condenser: false },
      legacy_source: "remote_wringer",
      legacy_lookup_error: nil,
      condenser_source: "local_fetch_cache"
    }
    cache_compare = mock
    cache_compare.expects(:call).with(uri: stale_cache.normalized_url, condenser_result: fetch_result).returns(comparison)

    result = Distillator::TransitionCheck.call(
      website: website,
      cache: stale_cache,
      run_fetch: true,
      fetch_cache_store: fetch_cache_store,
      cache_compare: cache_compare
    )

    assert_equal true, result.attempted_condenser_fetch
    assert_equal stale_cache.normalized_url, result.representative_url
    assert_equal fresh_cache, result.cache
    assert_equal :passed, result.fetch
    assert_equal comparison, result.comparison
  end

  test "latest successful condenser fetch stays passed when legacy lookup is incomplete" do
    website = build_website("legacy-lookup-incomplete")
    cache = build_cache(
      website: website,
      url: "https://legacy-lookup-incomplete.example/event",
      signals: { "transport_success" => true, "content_success" => true },
      health_status: "healthy"
    )
    website.transition_evidences.create!(
      url: cache.normalized_url,
      check_kind: "fetch_parity",
      status: "checked",
      checked_at: Time.current,
      details: {
        attempted_condenser_fetch: true,
        condenser_fetch_success: true,
        comparison_performed: false,
        legacy_lookup_status: "missing_config",
        legacy_lookup_error: "missing_config",
        reason: "legacy_lookup_missing_config"
      }
    )

    result = Distillator::TransitionCheck.call(website: website, cache: cache)

    assert_equal :passed, result.fetch
    assert_equal :review, result.status
    assert_includes result.warnings, "Needs review: legacy Wringer endpoint is not configured for this environment."
  end

  test "latest successful condenser fetch stays passed when legacy lookup is unreachable" do
    website = build_website("legacy-lookup-unreachable")
    cache = build_cache(
      website: website,
      url: "https://legacy-lookup-unreachable.example/event",
      signals: { "transport_success" => true, "content_success" => true },
      health_status: "healthy"
    )
    website.transition_evidences.create!(
      url: cache.normalized_url,
      check_kind: "fetch_parity",
      status: "checked",
      checked_at: Time.current,
      details: {
        attempted_condenser_fetch: true,
        condenser_fetch_success: true,
        comparison_performed: false,
        legacy_lookup_status: "unreachable",
        legacy_lookup_error: "connection refused",
        reason: "legacy_lookup_unreachable"
      }
    )

    result = Distillator::TransitionCheck.call(website: website, cache: cache)

    assert_equal :passed, result.fetch
    assert_equal :review, result.status
    assert_includes result.warnings, "Needs review: legacy Wringer lookup failed during the latest transition check."
  end

  test "run fetch skips compare when no representative webpage exists" do
    website = Website.create!(
      name: "No representative",
      seedurl: "no-representative",
      graph_name: "https://example.org/no-representative",
      default_language: "en",
      distillator_mode: "shadow"
    )
    fetch_cache_store = mock
    fetch_cache_store.expects(:fetch).never
    cache_compare = mock
    cache_compare.expects(:call).never

    result = Distillator::TransitionCheck.call(
      website: website,
      run_fetch: true,
      fetch_cache_store: fetch_cache_store,
      cache_compare: cache_compare
    )

    assert_equal false, result.attempted_condenser_fetch
    assert_nil result.representative_url
    assert_nil result.comparison
  end

  test "tourisme des chenaux style detail cache proceeds past fetch parity" do
    website = build_website("tourisme-des-chenaux")
    cache = build_cache(
      website: website,
      url: "https://tourismedeschenaux.ca/evenements",
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "content_type" => "html"
      },
      health_status: "healthy"
    )
    website.transition_evidences.create!(
      url: cache.normalized_url,
      check_kind: "fetch_parity",
      status: "checked",
      checked_at: Time.current,
      details: {
        attempted_condenser_fetch: true,
        representative_urls_checked: true
      }
    )

    result = Distillator::TransitionCheck.call(website: website, cache: cache)

    assert_equal :passed, result.fetch
    assert_not_includes result.blocking_issues, "Cannot activate yet: fetch check failed."
  end

  private

  def build_website(seedurl)
    Website.create!(
      name: seedurl,
      seedurl: seedurl,
      graph_name: "https://example.org/#{seedurl}",
      default_language: "en",
      distillator_mode: "shadow"
    )
  end

  def build_cache(website:, url:, signals:, health_status: "healthy")
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:#{website.seedurl}", rdfs_class: rdfs_classes(:one))
    Distillator::FetchCache.create!(
      uri_key: CGI.escape(url),
      normalized_url: url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: signals,
      final_url: url,
      health_status: health_status
    )
  end
end
