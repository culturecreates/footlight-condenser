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

  test "filters by term through sql" do
    matching = create_cache(uri: "http://example.org/needle", name: "Alpha")
    create_cache(uri: "http://example.org/other", name: "Beta")

    result = Distillator::CacheIndexQuery.call(
      filters: { term: "needle" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )

    assert_equal [matching.id], result.records.map(&:id)
  end

  test "filters by exact http response code and ignores blank invalid values" do
    not_found = create_cache(uri: "http://example.org/not-found", http_response_code: 404)
    ok = create_cache(uri: "http://example.org/success", http_response_code: 200)

    exact = Distillator::CacheIndexQuery.call(
      filters: { http_response_code: " 404 " },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )
    blank = Distillator::CacheIndexQuery.call(
      filters: { http_response_code: "" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )
    invalid = Distillator::CacheIndexQuery.call(
      filters: { http_response_code: "abc" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )

    assert_equal [not_found.id], exact.records.map(&:id)
    assert_equal [ok.id, not_found.id].sort, blank.records.map(&:id).sort
    assert_equal [ok.id, not_found.id].sort, invalid.records.map(&:id).sort
  end

  test "filters by has html and network status through sql" do
    with_html = create_cache(uri: "http://example.org/with-html", html: "<html>present</html>", signals: { "network_status" => "failed" })
    create_cache(uri: "http://example.org/without-html", html: nil, body: nil, signals: { "network_status" => "ok" })

    html_result = Distillator::CacheIndexQuery.call(
      filters: { has_html: "true" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )
    network_result = Distillator::CacheIndexQuery.call(
      filters: { network_status: "failed" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )

    assert_equal [with_html.id], html_result.records.map(&:id)
    assert_equal [with_html.id], network_result.records.map(&:id)
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

  test "filters redirected true rows with explicit sql predicate" do
    redirected = create_cache(
      uri: "http://example.org/redirected",
      final_url: "https://example.org/final",
      redirect_chain: ["http://example.org/redirected", "https://example.org/final"]
    )
    create_cache(uri: "http://example.org/direct", final_url: "http://example.org/direct", redirect_chain: [])

    result = Distillator::CacheIndexQuery.call(
      filters: { redirected: "true" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )

    assert_equal [redirected.id], result.records.map(&:id)
  end

  test "filters by status group nil and content type" do
    no_code = create_cache(uri: "http://example.org/nil-code", http_response_code: nil, signals: { "content_type" => "json" })
    create_cache(uri: "http://example.org/html", http_response_code: 200, signals: { "content_type" => "html" })

    nil_status = Distillator::CacheIndexQuery.call(
      filters: { status_group: "nil" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )
    content_type = Distillator::CacheIndexQuery.call(
      filters: { content_type: "json" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )

    assert_equal [no_code.id], nil_status.records.map(&:id)
    assert_equal [no_code.id], content_type.records.map(&:id)
  end

  test "filters by last attempt and last success time windows" do
    never_attempted = create_cache(uri: "http://example.org/never-attempted", scrape_date: nil)
    never_success = create_cache(uri: "http://example.org/never-success", successful_refresh: nil)
    create_cache(uri: "http://example.org/attempted-and-successful")

    last_attempt = Distillator::CacheIndexQuery.call(
      filters: { last_attempt: "never" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )
    last_success = Distillator::CacheIndexQuery.call(
      filters: { last_success: "never" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 10
    )

    assert_equal [never_attempted.id], last_attempt.records.map(&:id)
    assert_equal [never_success.id], last_success.records.map(&:id)
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
