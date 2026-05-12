require "test_helper"

class Distillator::CacheIndexQueryTest < ActiveSupport::TestCase
  setup do
    Distillator::FetchCache.delete_all
  end

  test "uses sql-backed filtering sorting and pagination when possible" do
    first = create_cache(uri: "http://example.org/a", http_response_code: 200, updated_at: 2.days.ago)
    second = create_cache(uri: "http://example.org/b", http_response_code: 404, updated_at: 1.day.ago)

    result = Distillator::CacheIndexQuery.call(
      filters: { status_group: "4xx" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )

    assert_kind_of ActiveRecord::Relation, result.records
    assert_kind_of ActiveRecord::Relation, result.summary_scope
    assert_equal [second.id], result.records.map(&:id)
    assert_equal 1, result.total_count
    assert_equal 1, result.total_pages
    assert_not_equal first.id, result.records.first.id
  end

  test "applies ruby-derived health filtering before pagination" do
    create_cache(uri: "http://example.org/healthy", http_response_code: 200)
    failed = create_cache(uri: "http://example.org/network", signals: { "network_status" => "failed", "content_type" => "html" })

    result = Distillator::CacheIndexQuery.call(
      filters: { health: "network_failed" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )

    assert_equal [failed.id], result.records.map(&:id)
    assert_kind_of ActiveRecord::Relation, result.summary_scope
  end

  test "applies ruby-derived hint filtering before pagination" do
    matching = create_cache(uri: "http://example.org/empty", hints: ["empty_body"])
    create_cache(uri: "http://example.org/other", hints: ["json_detected"])

    result = Distillator::CacheIndexQuery.call(
      filters: { hint: "empty_body" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )

    assert_equal [matching.id], result.records.map(&:id)
  end

  test "supports computed byte sorting before pagination" do
    small = create_cache(uri: "http://example.org/small", html: "<p>x</p>", body: "<p>x</p>")
    large = create_cache(uri: "http://example.org/large", html: "<div>#{'x' * 20}</div>", body: "<div>#{'x' * 20}</div>")

    result = Distillator::CacheIndexQuery.call(
      filters: {},
      sort: "html_bytes",
      direction: "desc",
      page: 1,
      per_page: 10
    )

    assert_equal [large.id, small.id], result.records.map(&:id)
  end

  test "filters by hint through sql without loading every record" do
    matching = create_cache(uri: "http://example.org/empty", hints: ["empty_body"])
    create_cache(uri: "http://example.org/other", hints: ["json_detected"])

    result = Distillator::CacheIndexQuery.call(
      filters: { hint: "empty_body" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )

    assert_equal [matching.id], result.records.map(&:id)
  end

  test "combines sql and ruby filtering before pagination" do
    create_cache(uri: "http://example.org/one", http_response_code: 404, hints: ["json_detected"])
    matching = create_cache(uri: "http://example.org/two", http_response_code: 404, hints: ["empty_body"])
    create_cache(uri: "http://example.org/three", http_response_code: 200, hints: ["empty_body"])

    result = Distillator::CacheIndexQuery.call(
      filters: { status_group: "4xx", hint: "empty_body" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )

    assert_equal [matching.id], result.records.map(&:id)
  end

  test "filters redirected false rows with explicit sql negation" do
    direct = create_cache(uri: "http://example.org/direct", final_url: "http://example.org/direct", redirect_chain: [])
    create_cache(
      uri: "http://example.org/redirected",
      final_url: "https://example.org/final",
      redirect_chain: ["http://example.org/redirected", "https://example.org/final"]
    )

    result = Distillator::CacheIndexQuery.call(
      filters: { redirected: "false" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )

    assert_kind_of ActiveRecord::Relation, result.records
    assert_equal [direct.id], result.records.map(&:id)
  end

  private

  def create_cache(uri:, html: "<html>cached</html>", body: html, name: "Cached", signals: { "network_status" => "ok", "content_type" => "html" }, hints: [], final_url: nil, redirect_chain: [], http_response_code: 200, scrape_date: Time.zone.now, successful_refresh: Time.zone.now, updated_at: Time.zone.now)
    cache = Distillator::FetchCache.new(
      uri_key: CGI.escape(uri),
      normalized_url: uri,
      html: html,
      body: body,
      name: name,
      scrape_date: scrape_date,
      successful_refresh: successful_refresh,
      http_response_code: http_response_code,
      headers: {},
      signals: signals,
      hints: hints,
      final_url: final_url,
      redirect_chain: redirect_chain
    )
    cache.created_at = updated_at
    cache.updated_at = updated_at
    cache.save!
    cache
  end
end
