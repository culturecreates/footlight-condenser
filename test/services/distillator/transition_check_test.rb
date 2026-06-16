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
    Distillator::WringerEndpoint.stubs(:current).returns(
      Distillator::WringerEndpoint::Result.new(
        compatibility_base_url: "http://compat.example",
        legacy_lookup_base_url: "http://wringer.example",
        compatibility_source: "DISTILLATOR_COMPAT_BASE_URL",
        state: :remote_configured,
        status_label: "Current Wringer: Remote configured",
        status_detail: "http://compat.example via DISTILLATOR_COMPAT_BASE_URL"
      )
    )
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
    cache_compare.expects(:call).with(uri: stale_cache.normalized_url, condenser_result: fetch_result, comparison_policy: :operator).returns(comparison)

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

  test "publishable representative webpages prefer nearest future then recently updated then recent past" do
    website = build_website("future-event-order")
    nearest_future = create_publishable_event_webpage(
      website,
      suffix: "nearest-future",
      url: "https://future-event-order.example/nearest-future",
      archive_date: Time.zone.parse("2026-06-01 12:00:00"),
      updated_at: Time.zone.parse("2026-05-24 10:00:00"),
      start_at: "2026-06-01T12:00:00-04:00"
    )
    later_future = create_publishable_event_webpage(
      website,
      suffix: "later-future",
      url: "https://future-event-order.example/later-future",
      archive_date: Time.zone.parse("2026-06-12 12:00:00"),
      updated_at: Time.zone.parse("2026-05-24 11:00:00"),
      start_at: "2026-06-12T12:00:00-04:00"
    )
    newest_nil_archive = create_publishable_event_webpage(
      website,
      suffix: "newest-nil-archive-event",
      url: "https://future-event-order.example/newest-nil-archive-event",
      archive_date: nil,
      updated_at: Time.zone.parse("2026-05-24 13:00:00"),
      start_at: "2026-06-20T20:00:00-04:00"
    )
    older_nil_archive = create_publishable_event_webpage(
      website,
      suffix: "older-nil-archive-event",
      url: "https://future-event-order.example/older-nil-archive-event",
      archive_date: nil,
      updated_at: Time.zone.parse("2026-05-24 12:00:00"),
      start_at: "2026-06-21T20:00:00-04:00"
    )
    recent_past = create_publishable_event_webpage(
      website,
      suffix: "recent-past",
      url: "https://future-event-order.example/recent-past",
      archive_date: Time.zone.parse("2026-03-15 19:00:00"),
      updated_at: Time.zone.parse("2026-05-22 09:00:00"),
      start_at: "2026-03-15T19:00:00-04:00"
    )
    create_publishable_event_webpage(
      website,
      suffix: "older-past",
      url: "https://future-event-order.example/older-past",
      archive_date: Time.zone.parse("2026-01-29 19:00:00"),
      updated_at: Time.zone.parse("2026-05-10 09:00:00"),
      start_at: "2026-01-29T19:00:00-05:00"
    )
    create_non_event_webpage(
      website,
      suffix: "about-page",
      url: "https://future-event-order.example/about-page",
      updated_at: Time.zone.parse("2026-05-24 13:00:00")
    )

    result = Distillator::TransitionCheck.call(website: website)

    assert_equal nearest_future, result.representative_webpage
    assert_equal [nearest_future, later_future, newest_nil_archive, older_nil_archive, recent_past], result.representative_webpages
    assert_equal "https://future-event-order.example/nearest-future", result.representative_url
    assert_equal 7, result.candidate_webpage_count
    assert_equal 6, result.publishable_event_page_count
    assert_equal 6, result.selected_candidate_tier_count
    assert_equal Distillator::TransitionCheck::SELECTION_RULE, result.selection_rule
  end

  test "publishable representative sampling follows the target matrix" do
    {
      1 => 1,
      3 => 3,
      5 => 5,
      20 => 5,
      26 => 6,
      50 => 10,
      100 => 20,
      125 => 25,
      300 => 25
    }.each do |publishable_count, expected_sample_size|
      website = build_website("sampling-#{publishable_count}")
      create_publishable_event_pages(website, publishable_count)

      result = Distillator::TransitionCheck.call(website: website)

      assert_equal publishable_count, result.publishable_event_page_count
      assert_equal expected_sample_size, result.representative_webpage_count
      assert_equal expected_sample_size, result.representative_webpages.count
      assert_equal publishable_count, result.selected_candidate_tier_count
      assert result.representative_webpages.all? { |webpage| webpage.rdfs_class.name == "Event" }, "expected only event pages for #{publishable_count}"
    end
  end

  test "representative webpages fall back to generic webpages in deterministic recency order when no publishable event pages exist" do
    website = build_website("generic-page-fallback")
    newest_page = create_non_event_webpage(
      website,
      suffix: "newest-page",
      url: "https://generic-page-fallback.example/newest-page",
      updated_at: Time.zone.parse("2026-05-24 12:00:00")
    )
    create_non_event_webpage(
      website,
      suffix: "middle-page",
      url: "https://generic-page-fallback.example/middle-page",
      updated_at: Time.zone.parse("2026-05-24 11:00:00")
    )
    create_non_event_webpage(
      website,
      suffix: "oldest-page",
      url: "https://generic-page-fallback.example/oldest-page",
      updated_at: Time.zone.parse("2026-05-24 10:00:00")
    )
    create_non_event_webpage(
      website,
      suffix: "fourth-page",
      url: "https://generic-page-fallback.example/fourth-page",
      updated_at: Time.zone.parse("2026-05-24 09:00:00")
    )
    create_event_webpage(
      website,
      suffix: "unpublishable-event",
      url: "https://generic-page-fallback.example/unpublishable-event",
      archive_date: Time.zone.parse("2026-05-24 08:00:00"),
      updated_at: Time.zone.parse("2026-05-24 08:00:00")
    )

    result = Distillator::TransitionCheck.call(website: website)

    assert_equal newest_page, result.representative_webpage
    assert_equal 3, result.representative_webpages.count
    assert_equal 5, result.candidate_webpage_count
    assert_equal 0, result.publishable_event_page_count
    assert_equal 5, result.selected_candidate_tier_count
  end

  test "candidate webpage count reflects all transition candidates, not only the selected tier" do
    website = build_website("candidate-count-honest")
    create_publishable_event_webpage(
      website,
      suffix: "future-one",
      url: "https://candidate-count-honest.example/future-one",
      archive_date: Time.zone.parse("2026-06-01 12:00:00"),
      updated_at: Time.zone.parse("2026-05-24 10:00:00"),
      start_at: "2026-06-01T12:00:00-04:00"
    )
    create_publishable_event_webpage(
      website,
      suffix: "future-two",
      url: "https://candidate-count-honest.example/future-two",
      archive_date: Time.zone.parse("2026-06-03 12:00:00"),
      updated_at: Time.zone.parse("2026-05-24 09:00:00"),
      start_at: "2026-06-03T12:00:00-04:00"
    )
    4.times do |index|
      create_publishable_event_webpage(
        website,
        suffix: "past-#{index}",
        url: "https://candidate-count-honest.example/past-#{index}",
        archive_date: Time.zone.parse("2026-02-#{index + 10} 12:00:00"),
        updated_at: Time.zone.parse("2026-05-2#{index} 08:00:00"),
        start_at: "2026-02-#{index + 10}T12:00:00-05:00"
      )
    end
    3.times do |index|
      create_non_event_webpage(
        website,
        suffix: "generic-#{index}",
        url: "https://candidate-count-honest.example/generic-#{index}",
        updated_at: Time.zone.parse("2026-05-2#{index} 07:00:00")
      )
    end

    result = Distillator::TransitionCheck.call(website: website)

    assert_equal 5, result.representative_webpage_count
    assert_equal 9, result.candidate_webpage_count
    assert_equal 6, result.publishable_event_page_count
    assert_equal 6, result.selected_candidate_tier_count
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
    assert_includes result.warnings, "Needs review: legacy Wringer lookup failed during the latest transition batch check."
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

  def create_event_webpage(website, suffix:, url:, archive_date:, updated_at: nil)
    webpage = website.webpages.create!(
      url: url,
      language: "en",
      rdf_uri: "rdf:#{website.seedurl}:#{suffix}",
      rdfs_class: rdfs_classes(:one),
      archive_date: archive_date
    )
    webpage.update_columns(archive_date: nil) if archive_date.nil?
    webpage.update_columns(updated_at: updated_at, created_at: updated_at) if updated_at.present?
    webpage.reload
  end

  def create_non_event_webpage(website, suffix:, url:, updated_at:)
    webpage = website.webpages.create!(
      url: url,
      language: "en",
      rdf_uri: "rdf:#{website.seedurl}:#{suffix}",
      rdfs_class: rdfs_classes(:person)
    )
    webpage.update_columns(updated_at: updated_at, created_at: updated_at)
    webpage.reload
  end

  def create_publishable_event_webpage(website, suffix:, url:, archive_date:, updated_at:, start_at:)
    webpage = create_event_webpage(
      website,
      suffix: suffix,
      url: url,
      archive_date: archive_date,
      updated_at: updated_at
    )
    create_publishable_statements_for(webpage, start_at: start_at)
    webpage
  end

  def create_publishable_event_pages(website, count)
    count.times.map do |index|
      archive_date, updated_at =
        if index < 10
          [
            Time.zone.parse("2026-06-#{format('%02d', index + 1)} 12:00:00"),
            Time.zone.parse("2026-05-24 10:#{format('%02d', index)}:00")
          ]
        elsif index < 20
          [
            nil,
            Time.zone.parse("2026-05-23 10:#{format('%02d', index - 10)}:00")
          ]
        else
          [
            Time.zone.parse("2026-02-#{format('%02d', ((index - 20) % 28) + 1)} 12:00:00"),
            Time.zone.parse("2026-05-22 10:#{format('%02d', index % 60)}:00")
          ]
        end

      create_publishable_event_webpage(
        website,
        suffix: "publishable-#{index}",
        url: "https://#{website.seedurl}.example/publishable-#{index}",
        archive_date: archive_date,
        updated_at: updated_at,
        start_at: "2026-06-#{format('%02d', (index % 28) + 1)}T12:00:00-04:00"
      )
    end
  end

  def create_publishable_statements_for(webpage, start_at:)
    [
      [properties(:four), "Representative title"],
      [properties(:location), '[["Salle","uri:place"]]'],
      [properties(:six), "[\"#{start_at}\"]"]
    ].each do |property, cache|
      source = Source.create!(
        website: webpage.website,
        property: property,
        language: "en",
        selected: true,
        algorithm_value: "transition-check-test"
      )

      Statement.create!(
        webpage: webpage,
        source: source,
        cache: cache,
        status: "ok"
      )
      Statement.where(webpage: webpage, source: source).update_all(status: "ok")
    end
  end
end
