require "test_helper"

class Distillator::TransitionCheckRunnerTest < ActiveSupport::TestCase
  include WebMock::API
  setup { WebMock.reset! }
  FetchResult = Struct.new(:cache, :transport_success_value, :content_success_value, :blocking_issue_key, :cache_hit, keyword_init: true) do
    def transport_success?
      transport_success_value
    end

    def content_success?
      content_success_value
    end
  end

  class FakeRefreshRunner
    def initialize(result = [])
      @result = result
      @calls = []
    end

    attr_reader :calls

    def call(**kwargs)
      @calls << kwargs
      @result
    end
  end

  class FakeExportService
    def initialize(actual:, expected:)
      @actual = actual
      @expected = expected
    end

    def call(seedurl:)
      @actual
    end

    def production_equivalent(seedurl:)
      @expected
    end
  end

  test "records current fetch error even when a last good body remains in the operational cache" do
    website = build_website
    cache = Distillator::FetchCache.find_by!(normalized_url: website.webpages.first.url)
    cache.update!(signals: { "network_status" => "failed", "transport_success" => false, "content_success" => false })
    failure = Distillator::FetchCacheStore::Result.new(cache: cache, cache_hit: false, body: cache.html,
      signals: cache.signals, fetch_error: { error_type: "TimeoutError", error: "Connection timed out" }, hints: ["timeout"])
    result = Distillator::TransitionCheckRunner.call(website: website,
      fetch_cache_store: FakeFetchCacheStore.new(cache.normalized_url => failure),
      cache_compare: fake_cache_compare_for(website), export_service: FakeExportService.new(actual: '{}', expected: '{}'))
    row = result.records[:fetch_parity].details["representative_url_results"].first
    assert_equal "failed", row["fetch_status"]
    assert_includes row["condenser_error"], "TimeoutError"
    assert_includes row["condenser_error"], "Connection timed out"
  end

  class FakeFetchCacheStore
    def initialize(results_by_url)
      @results_by_url = results_by_url
      @calls = []
    end

    attr_reader :calls

    def fetch(uri:, **options)
      @calls << options.merge(uri: uri)
      @results_by_url.fetch(uri)
    end
  end

  class FakeCacheCompare
    def initialize(results_by_url)
      @results_by_url = results_by_url
    end

    def call(uri:, **)
      @results_by_url[uri]
    end
  end

  test "active verification uses website mode and rejects a legacy fallback despite HTTP success" do
    website = build_website
    website.update_column(:distillator_mode, "active")
    cache = Distillator::FetchCache.find_by!(normalized_url: website.webpages.first.url)
    %w[native legacy].each do |path|
      fetcher = FakeFetchCacheStore.new(cache.normalized_url => Distillator::FetchCacheStore::Result.new(
        cache: cache, cache_hit: false, body: cache.html, signals: { transport_success: true, content_success: true }, fetch_path: path))
      result = Distillator::TransitionCheckRunner.call(website: website, verify_active_path: true,
        fetch_cache_store: fetcher, cache_compare: fake_cache_compare_for(website),
        export_service: FakeExportService.new(actual: '{}', expected: '{}'))
      assert_nil fetcher.calls.first[:mode]
      assert_equal true, fetcher.calls.first[:force_scrape]
      row = result.records[:fetch_parity].details["representative_url_results"].first
      assert_equal path == "native" ? "passed" : "failed", row["fetch_status"]
      assert_equal "active_path_did_not_use_condenser", row["fetch_reason"] if path == "legacy"
      assert_equal true, result.records[:fetch_parity].details["active_path_verification"]
      assert_equal "completed", website.latest_transition_run.progress["phase"]
    end
  end

  test "automated prechecks cannot certify two Wringer fallbacks as native parity" do
    website = build_website
    cache = Distillator::FetchCache.find_by!(normalized_url: website.webpages.first.url)
    fetcher = FakeFetchCacheStore.new(cache.normalized_url => Distillator::FetchCacheStore::Result.new(
      cache: cache, cache_hit: false, body: cache.html, signals: { transport_success: true, content_success: true }, fetch_path: "legacy"))
    result = Distillator::TransitionCheckRunner.call(website: website, require_native_path: true,
      fetch_cache_store: fetcher, cache_compare: fake_cache_compare_for(website),
      export_service: FakeExportService.new(actual: '{}', expected: '{}'))
    assert_equal "internal", fetcher.calls.first[:mode]
    assert_equal "failed", result.records[:fetch_parity].status
    assert_equal "native_fetch_not_established", result.records[:fetch_parity].details["representative_url_results"].first["fetch_reason"]
  end

  test "creates checked statement and export evidence from real transition checks without changing rollout mode" do
    website = build_website(with_webpage: false)
    cache = create_cache(website, signals: { "transport_success" => true, "content_success" => true })
    create_selected_statement(website.webpages.first, status: "ok")
    export_json = '[{"@id":"event:1","name":"Title"}]'

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      refresh_runner: FakeRefreshRunner.new,
      export_service: FakeExportService.new(actual: export_json, expected: export_json),
      transition_check_service: fake_transition_check_service(website: website, cache: cache),
      fetch_cache_store: fake_fetch_cache_store_for(website, cache),
      cache_compare: fake_cache_compare_for(website)
    ).call

    assert_equal "shadow", website.reload.distillator_mode
    assert_equal %w[export_diff fetch_parity statement_delta], result.records.keys.map(&:to_s).sort
    assert_equal %w[export_diff fetch_parity statement_delta], website.transition_evidences.order(:check_kind).pluck(:check_kind)
    assert_equal "checked", result.records[:fetch_parity].status
    assert_equal "checked", result.records[:statement_delta].status
    assert_equal "checked", result.records[:export_diff].status
    performance = result.records[:export_diff].details.fetch("performance")
    assert_equal %w[export fetch selection statements], performance.fetch("phases_ms").keys.sort
    assert_operator performance["total_ms"], :>=, 0
    assert_equal 0, performance.dig("reconciliation", "http_requests")
    assert performance["slowest_sources"].any?
    assert_equal cache.normalized_url, result.records[:fetch_parity].url
    assert_equal 0, result.records[:statement_delta].statement_delta
    assert_equal 0, result.records[:export_diff].rdf_added_count
    assert_equal 0, result.records[:export_diff].rdf_removed_count
    assert_equal 1, result.records[:statement_delta].details["representative_webpage_count"]
    assert_equal 1, result.records[:statement_delta].details["candidate_webpage_count"]
    assert_equal ["https://runner-site.example/event"], result.records[:statement_delta].details["representative_webpages"]
    assert_equal 0, result.records[:statement_delta].details["statements_refreshed_count"]
    assert_equal "paired_dsl", result.records[:statement_delta].details["comparison_basis"]
    assert_equal "completed", website.latest_transition_run.status
    assert_equal "current export vs production-equivalent export", result.records[:export_diff].details["export_basis"]
    assert_equal true, result.records[:export_diff].details["export_compared"]

    assert_difference("Distillator::TransitionEvidence.count", 3) do
      Distillator::TransitionCheckRunner.new(
        website: website,
        refresh_runner: FakeRefreshRunner.new,
        export_service: FakeExportService.new(actual: export_json, expected: export_json),
        transition_check_service: fake_transition_check_service(website: website, cache: cache),
        fetch_cache_store: fake_fetch_cache_store_for(website, cache), cache_compare: fake_cache_compare_for(website)
      ).call
    end
  end

  test "failed fetch records failed fetch check" do
    website = build_website(with_webpage: false)
    cache = create_cache(website, signals: { "transport_success" => false, "content_success" => false }, health_status: "attempt_failed")

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      transition_check_service: fake_transition_check_service(website: website, cache: cache, fetch: :failed),
      fetch_cache_store: fake_fetch_cache_store_for(website, cache, transport_success: false, content_success: false, blocking_issue_key: "cache_health_failed"),
      cache_compare: fake_cache_compare_for(website)
    ).call

    assert_equal "failed", result.records[:fetch_parity].status
    assert_equal "pending", result.records[:statement_delta].status
    assert_equal "fetch_failed_before_statement_refresh", result.records[:statement_delta].details["reason"]
    assert_equal 0, result.records[:statement_delta].details["statements_refreshed_count"]
    assert_equal "pending", result.records[:export_diff].status
    assert_equal "fetch_failed_before_export_comparison", result.records[:export_diff].details["reason"]
    assert_equal "Transition check incomplete: fetch failed, statements not evaluated, export blocked by fetch", result.flash_message
  end

  test "export diff records failed counts when comparison differs" do
    website = build_website(with_webpage: false)
    cache = create_cache(website, signals: { "transport_success" => true, "content_success" => true })
    create_selected_statement(website.webpages.first, status: "ok")

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      refresh_runner: FakeRefreshRunner.new,
      export_service: FakeExportService.new(
        actual: '<http://example.org/events/1> <http://schema.org/name> "Actual" .',
        expected: <<~NQUADS
          <http://example.org/events/1> <http://schema.org/name> "Expected" .
          <http://example.org/events/2> <http://schema.org/name> "Added" .
        NQUADS
      ),
      transition_check_service: fake_transition_check_service(website: website, cache: cache),
      fetch_cache_store: fake_fetch_cache_store_for(website, cache),
      cache_compare: fake_cache_compare_for(website)
    ).call

    assert_equal "failed", result.records[:export_diff].status
    assert_equal "failed", result.records[:export_diff].export_diff_status
    assert_operator result.records[:export_diff].rdf_added_count, :>, 0
    assert_operator result.records[:export_diff].rdf_removed_count, :>, 0
    assert_equal true, result.records[:export_diff].details["export_compared"]
  end

  test "checks record pending reasons when no representative webpages exist" do
    website = build_website(with_webpage: false)
    result = Distillator::TransitionCheckRunner.new(
      website: website,
      refresh_runner: FakeRefreshRunner.new,
      export_service: FakeExportService.new(actual: "[]", expected: "[]"),
      transition_check_service: fake_transition_check_service(website: website, cache: nil, representative_webpages: [], representative_webpage_count: 0, candidate_webpage_count: 0),
      fetch_cache_store: fake_fetch_cache_store_for(website, nil),
      cache_compare: fake_cache_compare_for(website)
    ).call

    assert_equal "pending", result.records[:fetch_parity].status
    assert_equal "no_representative_webpages", result.records[:fetch_parity].details["reason"]
    assert_equal "pending", result.records[:statement_delta].status
    assert_equal "no_representative_webpages", result.records[:statement_delta].details["reason"]
    assert_equal 0, result.records[:statement_delta].details["representative_webpage_count"]
    assert_equal "pending", result.records[:export_diff].status
    assert_equal "no_representative_webpages", result.records[:export_diff].details["reason"]
    assert_equal 0, result.records[:export_diff].details["representative_webpage_count"]
  end

  test "statement check records inconclusive when representative webpages have no selected statements" do
    website = build_website(with_webpage: false)
    cache = create_cache(website, signals: { "transport_success" => true, "content_success" => true })
    export_json = '[{"@id":"event:1","name":"Title"}]'

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      refresh_runner: FakeRefreshRunner.new,
      export_service: FakeExportService.new(actual: export_json, expected: export_json),
      transition_check_service: fake_transition_check_service(website: website, cache: cache),
      fetch_cache_store: fake_fetch_cache_store_for(website, cache),
      cache_compare: fake_cache_compare_for(website)
    ).call

    assert_equal "pending", result.records[:statement_delta].status
    assert_equal "paired_extraction_inconclusive", result.records[:statement_delta].details["reason"]
    assert_equal 0, result.records[:statement_delta].details["statements_refreshed_count"]
    assert_equal 0, result.records[:statement_delta].details["statements_failed_count"]
    assert_equal "Transition check incomplete: fetch checked, statements inconclusive, export checked", result.flash_message
  end

  test "fetch parity records review-needed difference without classifying it as fetch failure" do
    website = build_website(with_webpage: false)
    cache = create_cache(website, signals: { "transport_success" => true, "content_success" => true })
    create_selected_statement(website.webpages.first, status: "ok")
    export_json = '[{"@id":"event:1","name":"Title"}]'

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      refresh_runner: FakeRefreshRunner.new,
      export_service: FakeExportService.new(actual: export_json, expected: export_json),
      transition_check_service: fake_transition_check_service(
        website: website,
        cache: cache,
        comparison: {
          legacy_cache: { html: "<html>ok</html>" },
        legacy_source: "remote_wringer",
          legacy_lookup_status: "ok",
          legacy_lookup_error: nil,
          condenser_source: "local_fetch_cache",
          missing: { legacy: false, condenser: false },
          summary: {
            blocking_regressions: [],
            metadata_only_diffs: [],
            review_needed_diffs: [:content_type],
            unknown_diffs: []
          }
        }
      ),
      fetch_cache_store: fake_fetch_cache_store_for(website, cache),
      cache_compare: fake_cache_compare_for(website, website.webpages.first.url => {
        legacy_cache: { html: "<html>ok</html>" },
        legacy_source: "remote_wringer",
        legacy_lookup_status: "ok",
        legacy_lookup_error: nil,
        condenser_source: "local_fetch_cache",
        missing: { legacy: false, condenser: false },
        summary: {
          blocking_regressions: [],
          metadata_only_diffs: [],
          review_needed_diffs: [:content_type],
          unknown_diffs: []
        }
      })
    ).call

    assert_equal "checked", result.records[:fetch_parity].status
    assert_equal "review_needed_difference", result.records[:fetch_parity].details["reason"]
    assert_equal "operator", result.records[:fetch_parity].details["comparison_policy"]
  end

  test "fetch parity records metadata-only difference as checked metadata notes" do
    website = build_website(with_webpage: false)
    cache = create_cache(website, signals: { "transport_success" => true, "content_success" => true })
    create_selected_statement(website.webpages.first, status: "ok")
    export_json = '[{"@id":"event:1","name":"Title"}]'

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      refresh_runner: FakeRefreshRunner.new,
      export_service: FakeExportService.new(actual: export_json, expected: export_json),
      transition_check_service: fake_transition_check_service(
        website: website,
        cache: cache,
        comparison: {
          legacy_cache: { html: "<html>ok</html>" },
        legacy_source: "remote_wringer",
          legacy_lookup_status: "ok",
          legacy_lookup_error: nil,
          condenser_source: "local_fetch_cache",
          missing: { legacy: false, condenser: false },
          summary: {
            blocking_regressions: [],
            metadata_only_diffs: [:redirect_chain],
            review_needed_diffs: [],
            unknown_diffs: []
          }
        }
      ),
      fetch_cache_store: fake_fetch_cache_store_for(website, cache),
      cache_compare: fake_cache_compare_for(website, website.webpages.first.url => {
        legacy_cache: { html: "<html>ok</html>" },
        legacy_source: "remote_wringer",
        legacy_lookup_status: "ok",
        legacy_lookup_error: nil,
        condenser_source: "local_fetch_cache",
        missing: { legacy: false, condenser: false },
        summary: {
          blocking_regressions: [],
          metadata_only_diffs: [:redirect_chain],
          review_needed_diffs: [],
          unknown_diffs: []
        }
      })
    ).call

    assert_equal "checked", result.records[:fetch_parity].status
    assert_equal "metadata_only_difference", result.records[:fetch_parity].details["reason"]
    assert_equal "operator", result.records[:fetch_parity].details["comparison_policy"]
  end

  test "fetch parity stores per-url results and does not classify compare failures as fetch failures" do
    website = build_website(with_webpage: false)
    first = website.webpages.create!(url: "https://runner-site.example/one", language: "en", rdf_uri: "rdf:one", rdfs_class: rdfs_classes(:one))
    second = website.webpages.create!(url: "https://runner-site.example/two", language: "en", rdf_uri: "rdf:two", rdfs_class: rdfs_classes(:one))
    third = website.webpages.create!(url: "https://runner-site.example/three", language: "en", rdf_uri: "rdf:three", rdfs_class: rdfs_classes(:one))
    cache = Distillator::FetchCache.create!(
      uri_key: CGI.escape(first.url),
      normalized_url: first.url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: first.url,
      health_status: "healthy"
    )
    create_selected_statement(first, status: "ok")
    create_selected_statement(second, status: "ok")
    create_selected_statement(third, status: "ok")
    export_json = '[{"@id":"event:1","name":"Title"}]'

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      refresh_runner: FakeRefreshRunner.new,
      export_service: FakeExportService.new(actual: export_json, expected: export_json),
      transition_check_service: fake_transition_check_service(
        website: website,
        cache: cache,
        representative_webpages: [first, second, third]
      ),
      fetch_cache_store: FakeFetchCacheStore.new(
        first.url => fetch_result_for(cache: cache),
        second.url => fetch_result_for(cache: cache),
        third.url => fetch_result_for(cache: cache)
      ),
      cache_compare: FakeCacheCompare.new(
        first.url => { legacy_lookup_status: "ok", missing: { legacy: false, condenser: false }, summary: { blocking_regressions: [], metadata_only_diffs: [], review_needed_diffs: [], unknown_diffs: [] } },
        second.url => { legacy_lookup_status: "ok", missing: { legacy: false, condenser: false }, summary: { blocking_regressions: [:html_sha256], metadata_only_diffs: [], review_needed_diffs: [], unknown_diffs: [] } },
        third.url => { legacy_lookup_status: "unreachable", legacy_lookup_error: "timeout", missing: { legacy: false, condenser: false }, summary: { blocking_regressions: [], metadata_only_diffs: [], review_needed_diffs: [], unknown_diffs: [] } }
      )
    ).call

    representative_results = result.records[:fetch_parity].details["representative_url_results"]
    assert_equal 3, representative_results.size
    assert_equal %w[passed failed failed].sort, [result.records[:fetch_parity].details["representative_url_results"][0]["comparison_status"], result.records[:fetch_parity].details["representative_url_results"][1]["comparison_status"], result.records[:fetch_parity].status].map(&:to_s).sort
    assert_equal "cache_compare_blocking_regression", result.records[:fetch_parity].details["reason"]
    assert_equal "cache_compare", result.records[:fetch_parity].details["failed_layer"]
    assert_equal 1, result.records[:fetch_parity].details["affected_url_count"]
    refute_equal "cache_health_failed", result.records[:fetch_parity].details["reason"]
  end

  test "partial representative fetch failure blocks statement and export coverage only for the failed url" do
    website = build_website(with_webpage: false)
    first = website.webpages.create!(url: "https://runner-site.example/one", language: "en", rdf_uri: "rdf:one", rdfs_class: rdfs_classes(:one))
    second = website.webpages.create!(url: "https://runner-site.example/two", language: "en", rdf_uri: "rdf:two", rdfs_class: rdfs_classes(:one))
    third = website.webpages.create!(url: "https://runner-site.example/three", language: "en", rdf_uri: "rdf:three", rdfs_class: rdfs_classes(:one))
    cache = Distillator::FetchCache.create!(
      uri_key: CGI.escape(first.url),
      normalized_url: first.url,
      html: "<html>ok</html>",
      body: "<html>ok</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true },
      final_url: first.url,
      health_status: "healthy"
    )
    [first, second, third].each { |webpage| create_selected_statement(webpage, status: "ok") }
    export_json = '[{"@id":"event:1","name":"Title"}]'

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      refresh_runner: FakeRefreshRunner.new,
      export_service: FakeExportService.new(actual: export_json, expected: export_json),
      transition_check_service: fake_transition_check_service(
        website: website,
        cache: cache,
        representative_webpages: [first, second, third]
      ),
      fetch_cache_store: FakeFetchCacheStore.new(
        first.url => fetch_result_for(cache: cache),
        second.url => fetch_result_for(cache: cache),
        third.url => fetch_result_for(cache: cache, transport_success: false, content_success: false, blocking_issue_key: "cache_health_failed")
      ),
      cache_compare: fake_cache_compare_for(website)
    ).call

    assert_equal "failed", result.records[:fetch_parity].status
    assert_equal "fetch", result.records[:fetch_parity].details["failed_layer"]
    assert_equal 1, result.records[:fetch_parity].details["affected_url_count"]

    assert_equal "pending", result.records[:statement_delta].status
    assert_equal "partial_fetch_failed_before_statement_refresh", result.records[:statement_delta].details["reason"]
    assert_equal(
      {
        first.url => "passed",
        second.url => "passed",
        third.url => "blocked_by_fetch"
      },
      result.records[:statement_delta].details["representative_url_statement_results"].to_h { |row| [row["url"], row["status"]] }
    )

    assert_equal "pending", result.records[:export_diff].status
    assert_equal false, result.records[:export_diff].export_diff_checked
    assert_equal "partial", result.records[:export_diff].export_diff_status
    assert_equal "partial_fetch_failed_before_export_comparison", result.records[:export_diff].details["reason"]
    assert_equal false, result.records[:export_diff].details["export_compared"]
    assert_equal true, result.records[:export_diff].details["graph_diff_performed"]
    assert_equal(
      {
        first.url => "checked",
        second.url => "checked",
        third.url => "blocked_by_fetch"
      },
      result.records[:export_diff].details["representative_url_export_results"].to_h { |row| [row["url"], row["status"]] }
    )
    assert_equal "Transition check incomplete: fetch failed, statements inconclusive, export inconclusive", result.flash_message
  end

  test "timeout budget records incomplete evidence and preserves partial representative rows" do
    website = build_website(with_webpage: false)
    first = website.webpages.create!(url: "https://runner-site.example/one", language: "en", rdf_uri: "rdf:one", rdfs_class: rdfs_classes(:one))
    second = website.webpages.create!(url: "https://runner-site.example/two", language: "en", rdf_uri: "rdf:two", rdfs_class: rdfs_classes(:one))
    third = website.webpages.create!(url: "https://runner-site.example/three", language: "en", rdf_uri: "rdf:three", rdfs_class: rdfs_classes(:one))
    cache = create_fetch_cache_for_url(first.url, signals: { "transport_success" => true, "content_success" => true })
    create_selected_statement(first, status: "ok")
    create_selected_statement(second, status: "ok")
    create_selected_statement(third, status: "ok")
    refresh_runner = FakeRefreshRunner.new
    clock_values = [0.0, 0.0, 17.5, 17.5, 17.5]

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      refresh_runner: refresh_runner,
      export_service: FakeExportService.new(actual: "[]", expected: "[]"),
      transition_check_service: fake_transition_check_service(
        website: website,
        cache: cache,
        representative_webpages: [first, second, third]
      ),
      fetch_cache_store: FakeFetchCacheStore.new(
        first.url => fetch_result_for(cache: cache)
      ),
      cache_compare: fake_cache_compare_for(website),
      budget_seconds: 20,
      timeout_guard_seconds: 3,
      clock: -> { clock_values.shift || 17.5 }
    ).call

    assert_equal "failed", result.records[:fetch_parity].status
    assert_equal "transition_check_timeout_budget_exceeded", result.records[:fetch_parity].details["reason"]
    assert_equal 2, result.records[:fetch_parity].details["affected_url_count"]

    assert_equal "pending", result.records[:statement_delta].status
    assert_equal "transition_check_timeout_budget_exceeded", result.records[:statement_delta].details["reason"]
    assert_equal(
      {
        first.url => "inconclusive",
        second.url => "blocked_by_fetch",
        third.url => "blocked_by_fetch"
      },
      result.records[:statement_delta].details["representative_url_statement_results"].to_h { |row| [row["url"], row["status"]] }
    )

    assert_equal "pending", result.records[:export_diff].status
    assert_equal false, result.records[:export_diff].export_diff_checked
    assert_equal "pending", result.records[:export_diff].export_diff_status
    assert_equal "transition_check_timeout_budget_exceeded", result.records[:export_diff].details["reason"]
    assert_equal false, result.records[:export_diff].details["export_compared"]
    assert_equal(
      {
        first.url => "inconclusive",
        second.url => "blocked_by_fetch",
        third.url => "blocked_by_fetch"
      },
      result.records[:export_diff].details["representative_url_export_results"].to_h { |row| [row["url"], row["status"]] }
    )
    assert_empty refresh_runner.calls
  end

  test "captcha fetch failure is recorded explicitly" do
    website = build_website(with_webpage: false)
    cache = create_fetch_cache_for_url(
      "https://runner-site.example/captcha",
      signals: { "transport_success" => false, "content_success" => false, "blocking_issue_key" => "system_captcha" },
      health_status: "attempt_failed"
    )
    webpage = website.webpages.create!(url: cache.normalized_url, language: "en", rdf_uri: "rdf:captcha", rdfs_class: rdfs_classes(:one))

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      transition_check_service: fake_transition_check_service(website: website, cache: cache, representative_webpages: [webpage], fetch: :failed),
      fetch_cache_store: FakeFetchCacheStore.new(
        webpage.url => fetch_result_for(cache: cache, transport_success: false, content_success: false, blocking_issue_key: "system_captcha")
      ),
      cache_compare: fake_cache_compare_for(website)
    ).call

    assert_equal "failed", result.records[:fetch_parity].status
    assert_equal "captcha_detected", result.records[:fetch_parity].details["reason"]
    assert_equal "fetch", result.records[:fetch_parity].details["failed_layer"]
    assert_equal "captcha_detected", result.records[:statement_delta].details["representative_url_statement_results"].first["reason"]
    assert_equal "captcha_detected", result.records[:export_diff].details["representative_url_export_results"].first["reason"]
  end

  test "missing phantomjs api key is recorded explicitly for rendered fetch failure" do
    website = build_website(with_webpage: false)
    url = "https://runner-site.example/rendered"
    cache = create_fetch_cache_for_url(
      url,
      signals: {
        "transport_success" => false,
        "content_success" => false,
        "renderer_unavailable" => true,
        "use_phantomjs" => true
      },
      health_status: "attempt_failed"
    )
    webpage = website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:rendered", rdfs_class: rdfs_classes(:one))
    original_api_key = ENV["PHANTOMJS_API_KEY"]
    ENV["PHANTOMJS_API_KEY"] = nil

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      transition_check_service: fake_transition_check_service(website: website, cache: cache, representative_webpages: [webpage], fetch: :failed),
      fetch_cache_store: FakeFetchCacheStore.new(
        webpage.url => fetch_result_for(cache: cache, transport_success: false, content_success: false)
      ),
      cache_compare: fake_cache_compare_for(website)
    ).call

    assert_equal "phantomjs_api_key_missing", result.records[:fetch_parity].details["reason"]
  ensure
    ENV["PHANTOMJS_API_KEY"] = original_api_key
  end

  test "paired checks reuse snapshots without refreshing stored statements" do
    website = build_website(with_webpage: false)
    cache = create_fetch_cache_for_url("https://runner-site.example/event", signals: { "transport_success" => true, "content_success" => true })
    webpage = website.webpages.create!(url: cache.normalized_url, language: "en", rdf_uri: "rdf:runner-site", rdfs_class: rdfs_classes(:one))
    create_selected_statement(webpage, status: "initial")
    create_selected_statement(webpage, status: "initial")
    refresh_runner = FakeRefreshRunner.new
    export_json = '[{"@id":"event:1","name":"Title"}]'

    Distillator::TransitionCheckRunner.new(
      website: website,
      refresh_runner: refresh_runner,
      export_service: FakeExportService.new(actual: export_json, expected: export_json),
      transition_check_service: fake_transition_check_service(website: website, cache: cache, representative_webpages: [webpage]),
      fetch_cache_store: FakeFetchCacheStore.new(
        webpage.url => fetch_result_for(cache: cache)
      ),
      cache_compare: fake_cache_compare_for(website)
    ).call

    assert_empty refresh_runner.calls
  end

  test "rendered sources request a rendered candidate snapshot for paired extraction" do
    website = build_website
    create_selected_statement(website.webpages.first, status: "ok")
    website.sources.update_all(render_js: true)
    cache = Distillator::FetchCache.find_by!(normalized_url: website.webpages.first.url)
    store = fake_fetch_cache_store_for(website, cache)
    result = Distillator::TransitionCheckRunner.new(website: website,
      fetch_cache_store: store, cache_compare: fake_cache_compare_for(website),
      export_service: FakeExportService.new(actual: '[{"@id":"event:1"}]', expected: '[{"@id":"event:1"}]'),
      transition_check_service: fake_transition_check_service(website: website, cache: cache)).call
    assert_equal true, store.calls.first[:render_js]
    assert_equal "checked", result.records[:statement_delta].status
  end

  test "all page strict run persists its scope in every phase and blocks optional differences without updating statements" do
    website = build_website
    first = website.webpages.first
    stored = create_selected_statement(first, status: "ok")
    price = Property.create!(label: "Price", value_datatype: "MyString", uri: "https://example.org/strict-price", rdfs_class: rdfs_classes(:one))
    website.sources.create!(property: price, selected: true, language: "en", render_js: false, algorithm_value: "xpath=//span/text()")
    second = website.webpages.create!(url: "https://runner-site.example/other", language: "en", rdf_uri: "rdf:strict-other", rdfs_class: rdfs_classes(:one))
    caches = website.webpages.map do |page|
      cache = Distillator::FetchCache.find_by(normalized_url: page.url) || create_fetch_cache_for_url(page.url, signals: { transport_success: true, content_success: true })
      cache.update!(html: "<html><span>30</span></html>", body: "<html><span>30</span></html>")
      [page.url, fetch_result_for(cache: cache)]
    end.to_h
    legacy = website.webpages.to_h do |page|
      [page.url, { legacy_cache: { html: "<html><span>20</span></html>" }, legacy_lookup_status: "ok", missing: {},
        summary: { blocking_regressions: [], review_needed_diffs: [], metadata_only_diffs: [], unknown_diffs: [] } }]
    end
    before = stored.reload.attributes
    options = { sample_mode: "all", strictness: "strict" }
    result = Distillator::TransitionCheckRunner.call(website: website, check_options: options,
      fetch_cache_store: FakeFetchCacheStore.new(caches), cache_compare: FakeCacheCompare.new(legacy),
      export_service: FakeExportService.new(actual: '{"@id":"event:1"}', expected: '{"@id":"event:1"}'))
    assert_equal options.stringify_keys, website.latest_transition_run.check_options
    result.records.each_value { |record| assert_equal options.stringify_keys, record.details["check_options"] }
    statements = result.records[:statement_delta]
    assert_equal 2, statements.details["representative_webpage_count"]
    assert_equal 2, statements.details["compared_webpage_count"]
    assert_equal "failed", statements.status
    assert_equal "strict_statement_parity_failed", statements.details["reason"]
    assert_equal ["Price"], statements.details["critical_failing_statements"].map { |entry| entry["property_label"] }.uniq
    assert_equal before, stored.reload.attributes
    assert_equal "shadow", website.reload.distillator_mode
    assert_equal :failed, Distillator::TransitionStatus.call(website: website).statements
  end

  test "additional diagnostics and body drift do not block matching strict statements and export" do
    website = build_website
    page = website.webpages.first
    create_selected_statement(page, status: "ok")
    cache = Distillator::FetchCache.find_by!(normalized_url: page.url)
    cache.update!(http_response_code: 200)
    endpoint = Distillator::WringerEndpoint::Result.new(legacy_lookup_base_url: "https://legacy.example")
    Distillator::WringerEndpoint.stubs(:current).returns(endpoint)
    request = stub_request(:get, "https://legacy.example/websites/wring.json")
      .with(query: { uri: page.url, force_scrape: "true" })
      .to_return(body: { html: cache.html + '<!-- Different tracking markup -->', http_code: 200 }.to_json)
    result = Distillator::TransitionCheckRunner.call(website: website,
      check_options: { sample_mode: "all", strictness: "strict" },
      fetch_cache_store: fake_fetch_cache_store_for(website, cache),
      export_service: FakeExportService.new(actual: '{"@id":"event:1"}', expected: '{"@id":"event:1"}'))
    assert_equal "metadata_only_difference", result.records[:fetch_parity].details["reason"]
    assert result.records.values.all? { |record| record.status == "checked" }
    status = Distillator::TransitionStatus.for_completed_run(website: website, run: website.latest_transition_run)
    assert_equal :ready, status.status
    assert_empty status.warnings
    assert_equal "shadow", website.reload.distillator_mode
    assert_requested request, times: 1
    assert_equal "fresh_both", result.records[:fetch_parity].details["fetch_basis"]
    assert result.records[:fetch_parity].details["representative_url_results"].first.dig("legacy_fetch", "force_scrape")
  end

  test "failed fresh Wringer scrape cannot compare its retained last good HTML" do
    website = build_website
    page = website.webpages.first
    create_selected_statement(page, status: "ok")
    cache = Distillator::FetchCache.find_by!(normalized_url: page.url)
    endpoint = Distillator::WringerEndpoint::Result.new(legacy_lookup_base_url: "https://legacy.example")
    Distillator::WringerEndpoint.stubs(:current).returns(endpoint)
    stub_request(:get, "https://legacy.example/websites/wring.json")
      .with(query: { uri: page.url, force_scrape: "true" })
      .to_return(body: { html: cache.html, http_code: 503 }.to_json)
    native = fake_fetch_cache_store_for(website, cache)

    result = Distillator::TransitionCheckRunner.call(website: website, fetch_cache_store: native,
      export_service: FakeExportService.new(actual: '{}', expected: '{}'))

    assert_equal "legacy_lookup_unreachable", result.records[:fetch_parity].details["reason"]
    assert_equal "pending", result.records[:statement_delta].status
    assert_empty result.records[:statement_delta].details["statement_artifacts"]
    assert_equal true, native.calls.first[:force_scrape]
    assert_equal false, native.calls.first[:render_js]
    assert_not Distillator::TransitionStatus.call(website: website).review_activation_eligible
    assert_not_requested :get, "https://legacy.example/websites.json"
  end

  test "runner cannot silently substitute a different scope for a recorded job" do
    website = build_website
    run = Distillator::TransitionRun.request!(website: website, options: { sample_mode: "all", strictness: "strict" }).run
    assert_raises(ArgumentError) { Distillator::TransitionCheckRunner.new(website: website, transition_run: run, check_options: {}) }
  end

  test "a large check near lease expiry records incomplete coverage rather than claiming all pages were checked" do
    website = build_website
    cache = Distillator::FetchCache.find_by!(normalized_url: website.webpages.first.url)
    run = Distillator::TransitionRun.request!(website: website, options: { sample_mode: "all", strictness: "strict" }).run
    run.update_column(:requested_at, 59.minutes.ago)
    store = mock
    store.expects(:fetch).never
    compare = mock
    compare.expects(:call).never
    run.execute do
      Distillator::TransitionCheckRunner.call(website: website, transition_run: run,
        transition_check_service: fake_transition_check_service(website: website, cache: cache),
        fetch_cache_store: store, cache_compare: compare)
    end
    detail = Distillator::ShadowSiteDetail.call(website: website)
    assert_equal 1, detail.checked_scope[:representative_webpage_count]
    assert_equal 0, detail.checked_scope[:fetch_attempted_webpage_count]
    assert_equal 0, detail.checked_scope[:compared_webpage_count]
    assert_includes ApplicationController.helpers.shadow_report_scope_lines(detail.checked_scope), "Compared 0 of 1 selected pages. Condenser fetch attempts: 0."
    assert_equal :failed, detail.transition_status.fetch
    assert_not detail.transition_status.review_activation_eligible
  end

  private

  def build_website(with_webpage: true)
    website = Website.create!(
      name: "Runner site",
      seedurl: "runner-site",
      graph_name: "https://example.org/runner-site",
      default_language: "en",
      distillator_mode: "shadow"
    )
    create_cache(website, signals: { "transport_success" => true, "content_success" => true }) if with_webpage
    website
  end

  def create_cache(website, signals:, health_status: "healthy")
    url = "https://runner-site.example/event"
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:runner-site", rdfs_class: rdfs_classes(:one))
    create_fetch_cache_for_url(url, signals: signals, health_status: health_status)
  end

  def create_fetch_cache_for_url(url, signals:, health_status: "healthy")
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

  def create_selected_statement(webpage, status:, property: properties(:four), cache: "Runner Title")
    # Paired extraction needs required sources, independent of existing statements.
    %w[Title Dates Location].each do |label|
      next if webpage.website.sources.joins(:property).where(properties: { label: label }).exists?
      definition = Property.create!(label: label, value_datatype: "MyString", uri: "https://example.org/#{label}", rdfs_class: rdfs_classes(:one))
      webpage.website.sources.create!(property: definition, algorithm_value: "manual=Required #{label}", selected: true, language: "en", render_js: false)
    end
    source = Source.create!(
      algorithm_value: "manual=Runner Title",
      selected: true,
      selected_by: "test",
      language: "en",
      render_js: false,
      property: property,
      website: webpage.website
    )
    statement = Statement.create!(
      cache: cache,
      status: status,
      status_origin: "transition_check_test",
      cache_refreshed: 1.hour.ago,
      cache_changed: 1.hour.ago,
      source: source,
      webpage: webpage,
      selected_individual: true
    )
    statement.update_columns(
      cache: cache,
      status: status,
      cache_refreshed: 1.hour.ago,
      cache_changed: 1.hour.ago
    )
    statement
  end

  def fetch_result_for(cache:, transport_success: true, content_success: true, blocking_issue_key: nil)
    FetchResult.new(
      cache: cache,
      transport_success_value: transport_success,
      content_success_value: content_success,
      blocking_issue_key: blocking_issue_key
    )
  end

  def fake_fetch_cache_store_for(website, cache, transport_success: true, content_success: true, blocking_issue_key: nil)
    results = website.webpages.index_with do
      fetch_result_for(
        cache: cache,
        transport_success: transport_success,
        content_success: content_success,
        blocking_issue_key: blocking_issue_key
      )
    end
    FakeFetchCacheStore.new(results.transform_keys(&:url))
  end

  def fake_cache_compare_for(website, overrides = {})
    defaults = website.webpages.index_with do
      {
        legacy_cache: { html: "<html>ok</html>" },
        legacy_source: "remote_wringer",
        legacy_lookup_status: "ok",
        legacy_lookup_error: nil,
        condenser_source: "local_fetch_cache",
        missing: { legacy: false, condenser: false },
        summary: {
          blocking_regressions: [],
          metadata_only_diffs: [],
          review_needed_diffs: [],
          unknown_diffs: []
        }
      }
    end
    FakeCacheCompare.new(defaults.transform_keys(&:url).merge(overrides))
  end

  def fake_transition_check_service(website:, cache:, fetch: :passed, representative_webpages: nil, representative_webpage_count: nil, candidate_webpage_count: nil, publishable_event_page_count: nil, comparison: nil)
    representative_webpages = representative_webpages.nil? ? Array(website.webpages.first).compact : representative_webpages
    representative_webpage = representative_webpages.first

    stub(
      call: Distillator::TransitionCheck::Result.new(
        website_id: website.id,
        website: website,
        mode: website.distillator_mode.to_sym,
        priority: false,
        active_backend: :wringer,
        latest_cache_status: cache&.health_status.to_s.presence || "unknown",
        cache_present: cache.present?,
        compare_available: true,
        blocking_issues: [],
        warnings: [],
        promotable: false,
        status: :review,
        fetch: fetch,
        statements: :missing,
        export: :missing,
        representative_webpage: representative_webpage,
        representative_webpages: representative_webpages,
        representative_url: representative_webpage&.url,
        representative_webpage_count: representative_webpage_count || representative_webpages.count,
        candidate_webpage_count: candidate_webpage_count || representative_webpages.count,
        publishable_event_page_count: publishable_event_page_count || representative_webpages.count,
        selection_rule: Distillator::TransitionCheck::SELECTION_RULE,
        attempted_condenser_fetch: false,
        condenser_fetch_result: nil,
        comparison: comparison,
        comparison_policy: :operator,
        cache: cache,
        cache_link_payload: {},
        primary_action: "Run transition batch check."
      )
    )
  end
end
