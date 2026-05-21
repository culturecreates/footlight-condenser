require "test_helper"

class Distillator::TransitionCheckRunnerTest < ActiveSupport::TestCase
  class FakeRefreshRunner
    def initialize(result = [])
      @result = result
    end

    def call(...)
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

  test "creates checked statement and export evidence from real transition checks without changing rollout mode" do
    website = build_website(with_webpage: false)
    cache = create_cache(website, signals: { "transport_success" => true, "content_success" => true })
    create_selected_statement(website.webpages.first, status: "ok")
    export_json = '[{"@id":"event:1","name":"Title"}]'

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      refresh_runner: FakeRefreshRunner.new,
      export_service: FakeExportService.new(actual: export_json, expected: export_json)
    ).call

    assert_equal "shadow", website.reload.distillator_mode
    assert_equal %w[export_diff fetch_parity statement_delta], result.records.keys.map(&:to_s).sort
    assert_equal %w[export_diff fetch_parity statement_delta], website.transition_evidences.order(:check_kind).pluck(:check_kind)
    assert_equal "checked", result.records[:fetch_parity].status
    assert_equal "checked", result.records[:statement_delta].status
    assert_equal "checked", result.records[:export_diff].status
    assert_equal cache.normalized_url, result.records[:fetch_parity].url
    assert_equal 0, result.records[:statement_delta].statement_delta
    assert_equal 0, result.records[:export_diff].rdf_added_count
    assert_equal 0, result.records[:export_diff].rdf_removed_count
    assert_equal 1, result.records[:statement_delta].details["representative_webpage_count"]
    assert_equal 1, result.records[:statement_delta].details["candidate_webpage_count"]
    assert_equal ["https://runner-site.example/event"], result.records[:statement_delta].details["representative_webpages"]
    assert_equal 1, result.records[:statement_delta].details["statements_refreshed_count"]
    assert_equal "current export vs production-equivalent export", result.records[:export_diff].details["export_basis"]
    assert_equal true, result.records[:export_diff].details["export_compared"]

    assert_no_difference("Distillator::TransitionEvidence.count") do
      Distillator::TransitionCheckRunner.new(
        website: website,
        refresh_runner: FakeRefreshRunner.new,
        export_service: FakeExportService.new(actual: export_json, expected: export_json)
      ).call
    end
  end

  test "failed fetch records failed fetch check" do
    website = build_website(with_webpage: false)
    create_cache(website, signals: { "transport_success" => false, "content_success" => false }, health_status: "attempt_failed")

    result = Distillator::TransitionCheckRunner.call(website: website)

    assert_equal "failed", result.records[:fetch_parity].status
    assert_equal "pending", result.records[:statement_delta].status
    assert_equal "fetch_failed_before_statement_refresh", result.records[:statement_delta].details["reason"]
    assert_equal 0, result.records[:statement_delta].details["statements_refreshed_count"]
    assert_equal "pending", result.records[:export_diff].status
    assert_equal "fetch_failed_before_export_comparison", result.records[:export_diff].details["reason"]
  end

  test "statement check records failed reason when refresh fails" do
    website = build_website(with_webpage: false)
    create_cache(website, signals: { "transport_success" => true, "content_success" => true })
    create_selected_statement(website.webpages.first, status: "ok")
    export_json = '[{"@id":"event:1","name":"Title"}]'

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      refresh_runner: FakeRefreshRunner.new([{ "Property id 1" => { cache: ["abort_update"] } }]),
      export_service: FakeExportService.new(actual: export_json, expected: export_json)
    ).call

    assert_equal "failed", result.records[:statement_delta].status
    assert_equal "statement_refresh_failed", result.records[:statement_delta].details["reason"]
    assert_equal 1, result.records[:statement_delta].details["statements_failed_count"]
    assert_equal ["https://runner-site.example/event"], result.records[:statement_delta].details["representative_webpages"]
  end

  test "export diff records failed counts when comparison differs" do
    website = build_website(with_webpage: false)
    create_cache(website, signals: { "transport_success" => true, "content_success" => true })
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
      )
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
      export_service: FakeExportService.new(actual: "[]", expected: "[]")
    ).call

    assert_equal "pending", result.records[:statement_delta].status
    assert_equal "no_representative_webpages", result.records[:statement_delta].details["reason"]
    assert_equal 0, result.records[:statement_delta].details["representative_webpage_count"]
    assert_equal "pending", result.records[:export_diff].status
    assert_equal "no_representative_webpages", result.records[:export_diff].details["reason"]
    assert_equal 0, result.records[:export_diff].details["representative_webpage_count"]
  end

  test "statement check records inconclusive when representative webpages have no selected statements" do
    website = build_website(with_webpage: false)
    create_cache(website, signals: { "transport_success" => true, "content_success" => true })
    export_json = '[{"@id":"event:1","name":"Title"}]'

    result = Distillator::TransitionCheckRunner.new(
      website: website,
      refresh_runner: FakeRefreshRunner.new,
      export_service: FakeExportService.new(actual: export_json, expected: export_json)
    ).call

    assert_equal "pending", result.records[:statement_delta].status
    assert_equal "no_selected_statements", result.records[:statement_delta].details["reason"]
    assert_equal 0, result.records[:statement_delta].details["statements_refreshed_count"]
    assert_equal 0, result.records[:statement_delta].details["statements_failed_count"]
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

  def create_selected_statement(webpage, status:)
    source = Source.create!(
      algorithm_value: "manual=Runner Title",
      selected: true,
      selected_by: "test",
      language: "en",
      render_js: false,
      property: properties(:four),
      website: webpage.website
    )
    Statement.create!(
      cache: "Runner Title",
      status: status,
      status_origin: "transition_check_test",
      cache_refreshed: 1.hour.ago,
      cache_changed: 1.hour.ago,
      source: source,
      webpage: webpage,
      selected_individual: true
    )
  end
end
