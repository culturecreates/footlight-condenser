require "test_helper"

class Distillator::ShadowReportQueryTest < ActiveSupport::TestCase
  test "defaults to a bounded shadow-only report" do
    30.times do |index|
      create_shadow_site(name: format("Shadow %02d", index), seedurl: "shadow-#{index}", recommendation: :ready)
    end
    create_website(name: "Legacy site", seedurl: "legacy-site", mode: "legacy")
    create_website(name: "Active site", seedurl: "active-site", mode: "active")

    result = Distillator::ShadowReportQuery.call(
      filters: {},
      sort: Distillator::ShadowReportQuery::DEFAULT_SORT,
      direction: Distillator::ShadowReportQuery::DEFAULT_DIRECTION,
      page: 1,
      per_page: Distillator::ShadowReportQuery::DEFAULT_LIMIT
    )

    names = result.records.map { |row| row.website.name }

    assert_equal Distillator::ShadowReportQuery::DEFAULT_LIMIT, result.records.length
    assert_equal 30, result.total_count
    assert_includes names, "Shadow 00"
    refute_includes names, "Legacy site"
    refute_includes names, "Active site"
  end

  test "limit cannot exceed the maximum" do
    101.times do |index|
      create_shadow_site(name: format("Max %03d", index), seedurl: "max-#{index}", recommendation: :ready)
    end

    result = Distillator::ShadowReportQuery.call(
      filters: {},
      sort: Distillator::ShadowReportQuery::DEFAULT_SORT,
      direction: Distillator::ShadowReportQuery::DEFAULT_DIRECTION,
      page: 1,
      per_page: 999
    )

    assert_equal Distillator::ShadowReportQuery::MAX_LIMIT, result.per_page
    assert_equal Distillator::ShadowReportQuery::MAX_LIMIT, result.records.length
    assert_equal 101, result.total_count
  end

  test "default report paginates many shadow sites without showing them all on page one" do
    40.times do |index|
      create_shadow_site(name: format("Paged %02d", index), seedurl: "visible-#{index}", recommendation: :ready)
    end

    page_one = Distillator::ShadowReportQuery.call(
      filters: {},
      sort: Distillator::ShadowReportQuery::DEFAULT_SORT,
      direction: Distillator::ShadowReportQuery::DEFAULT_DIRECTION,
      page: 1,
      per_page: Distillator::ShadowReportQuery::DEFAULT_LIMIT
    )
    page_two = Distillator::ShadowReportQuery.call(
      filters: {},
      sort: Distillator::ShadowReportQuery::DEFAULT_SORT,
      direction: Distillator::ShadowReportQuery::DEFAULT_DIRECTION,
      page: 2,
      per_page: Distillator::ShadowReportQuery::DEFAULT_LIMIT
    )

    assert_equal 25, page_one.records.length
    assert_equal 15, page_two.records.length
    refute_equal page_one.records.map { |row| row.website.name }, page_two.records.map { |row| row.website.name }
  end

  test "filters by recommendation, health severity, issue key, and search term" do
    create_shadow_site(name: "Ready site", seedurl: "ready-site", recommendation: :ready, issue_key: nil, health_severity: "ok")
    create_shadow_site(name: "Blocked site", seedurl: "blocked-site", recommendation: :blocked, issue_key: "timeout", health_severity: "high")
    create_shadow_site(name: "Review queue", seedurl: "review-site", recommendation: :review, issue_key: "queue_it", health_severity: "low")

    filtered = Distillator::ShadowReportQuery.call(
      filters: { recommendation: "review", health_severity: "ok", primary_issue_key: "queue_it", term: "queue" },
      sort: Distillator::ShadowReportQuery::DEFAULT_SORT,
      direction: Distillator::ShadowReportQuery::DEFAULT_DIRECTION,
      page: 1,
      per_page: 25
    )

    assert_equal ["Review queue"], filtered.records.map { |row| row.website.name }
  end

  test "sorts by website, recommendation, latest attempt, latest successful refresh, and issue key" do
    create_shadow_site(name: "Sort fixture Zulu ready", seedurl: "sort-fixture-zulu-ready", recommendation: :ready, scrape_date: 3.hours.ago, successful_refresh: 3.hours.ago)
    create_shadow_site(name: "Sort fixture Alpha blocked", seedurl: "sort-fixture-alpha-blocked", recommendation: :blocked, issue_key: "timeout", scrape_date: 1.hour.ago, successful_refresh: 5.hours.ago)
    create_shadow_site(name: "Sort fixture Beta review", seedurl: "sort-fixture-beta-review", recommendation: :review, issue_key: "queue_it", scrape_date: 2.hours.ago, successful_refresh: 2.hours.ago)

    by_recommendation = Distillator::ShadowReportQuery.call(filters: { term: "Sort fixture" }, sort: "recommendation", direction: "asc", page: 1, per_page: 25)
    assert_equal ["Sort fixture Alpha blocked", "Sort fixture Beta review", "Sort fixture Zulu ready"], by_recommendation.records.map { |row| row.website.name }

    by_latest_attempt = Distillator::ShadowReportQuery.call(filters: { term: "Sort fixture" }, sort: "latest_attempt", direction: "desc", page: 1, per_page: 25)
    assert_equal ["Sort fixture Alpha blocked", "Sort fixture Beta review", "Sort fixture Zulu ready"], by_latest_attempt.records.map { |row| row.website.name }

    by_latest_success = Distillator::ShadowReportQuery.call(filters: { term: "Sort fixture" }, sort: "latest_successful_refresh", direction: "desc", page: 1, per_page: 25)
    assert_equal ["Sort fixture Beta review", "Sort fixture Zulu ready", "Sort fixture Alpha blocked"], by_latest_success.records.map { |row| row.website.name }

    by_issue_key = Distillator::ShadowReportQuery.call(filters: { term: "Sort fixture" }, sort: "issue_key", direction: "asc", page: 1, per_page: 25)
    assert_equal ["Sort fixture Zulu ready", "Sort fixture Beta review", "Sort fixture Alpha blocked"], by_issue_key.records.map { |row| row.website.name }
  end

  test "paginates rows" do
    3.times do |index|
      create_shadow_site(name: "Paged #{index}", seedurl: "paged-#{index}", recommendation: :ready)
    end

    page_one = Distillator::ShadowReportQuery.call(filters: { term: "Paged" }, sort: "website", direction: "asc", page: 1, per_page: 2)
    page_two = Distillator::ShadowReportQuery.call(filters: { term: "Paged" }, sort: "website", direction: "asc", page: 2, per_page: 2)

    assert_equal 2, page_one.records.length
    assert_equal 1, page_two.records.length
    assert_equal 3, page_one.total_count
    assert_equal 2, page_one.total_pages
    assert_includes page_one.records.map { |row| row.website.name } + page_two.records.map { |row| row.website.name }, "Paged 0"
    assert_includes page_one.records.map { |row| row.website.name } + page_two.records.map { |row| row.website.name }, "Paged 1"
    assert_includes page_one.records.map { |row| row.website.name } + page_two.records.map { |row| row.website.name }, "Paged 2"
  end

  test "latest cache rows are loaded without html or body blobs" do
    create_shadow_site(
      name: "Blob guard",
      seedurl: "blob-guard",
      recommendation: :ready,
      html: "<html>blob</html>",
      body: "<html>blob body</html>"
    )

    result = Distillator::ShadowReportQuery.call(filters: {}, sort: "website", direction: "asc", page: 1, per_page: 25)
    cache = result.records.first.cache

    assert cache.present?
    assert_raises(ActiveModel::MissingAttributeError) { cache.html }
    assert_raises(ActiveModel::MissingAttributeError) { cache.body }
  end

  test "cache with trailing slash difference still maps to the website" do
    website = create_website(name: "Slash site", seedurl: "slash-site", mode: "shadow")
    website.webpages.create!(
      id: next_id,
      url: "https://slash-site.example/event/",
      language: "en",
      rdf_uri: "adr:slash-site",
      rdfs_class: rdfs_classes(:one)
    )
    Distillator::FetchCache.create!(
      id: next_id,
      uri_key: CGI.escape("https://slash-site.example/event"),
      normalized_url: "https://slash-site.example/event",
      html: "<html>cached</html>",
      body: "<html>cached</html>",
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true, "export_diff_checked" => true },
      final_url: "https://slash-site.example/event"
    )

    result = Distillator::ShadowReportQuery.call(filters: {}, sort: "website", direction: "asc", page: 1, per_page: 25)

    assert_includes result.records.map { |row| row.website.name }, "Slash site"
  end

  private

  def create_website(name:, seedurl:, mode:)
    Website.create!(
      id: next_id,
      name: name,
      seedurl: seedurl,
      graph_name: "https://#{seedurl}.example/graph",
      default_language: "en",
      distillator_mode: mode
    )
  end

  def create_shadow_site(name:, seedurl:, recommendation:, issue_key: nil, health_severity: "ok", scrape_date: 1.hour.ago, successful_refresh: 1.hour.ago, html: "<html>cached</html>", body: "<html>cached</html>")
    website = create_website(name: name, seedurl: seedurl, mode: "shadow")
    url = "https://#{seedurl}.example/event"
    website.webpages.create!(
      id: next_id,
      url: url,
      language: "en",
      rdf_uri: "adr:#{seedurl}",
      rdfs_class: rdfs_classes(:one)
    )

    attrs = {
      uri_key: CGI.escape(url),
      normalized_url: url,
      name: name,
      html: html,
      body: body,
      http_response_code: 200,
      scrape_date: scrape_date,
      successful_refresh: successful_refresh,
      headers: {},
      signals: {
        "transport_success" => true,
        "content_success" => true,
        "primary_issue_key" => issue_key
      }.compact,
      hints: Array(issue_key).compact,
      final_url: url,
      redirect_chain: [],
      health_status: "healthy",
      health_severity: health_severity,
      primary_issue_key: issue_key,
      primary_issue_label: issue_key&.humanize,
      primary_issue_severity: issue_key.present? ? (recommendation == :blocked ? "failed" : "warning") : nil
    }

    attrs[:signals] = attrs[:signals].merge("export_diff_checked" => true, "statement_count_delta_acceptable" => true) if recommendation == :ready

    case recommendation
    when :blocked
      attrs[:health_status] = "attempt_failed"
      attrs[:signals] = { "transport_success" => false, "content_success" => false, "primary_issue_key" => issue_key, "primary_issue_severity" => "failed" }.compact
    when :review
      attrs[:health_status] = "redirect_changed"
      attrs[:signals] = { "transport_success" => true, "primary_issue_key" => issue_key, "primary_issue_severity" => "warning" }.compact
      attrs[:redirected] = true
      attrs[:final_url] = "#{url}/redirected"
    end

    Distillator::FetchCache.create!(attrs.merge(id: next_id))
    website
  end

  def next_id
    @next_id ||= 1_000_000_000 + ((Process.pid % 10_000) * 100_000)
    @next_id += 1
  end
end
