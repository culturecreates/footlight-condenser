require "test_helper"
require "minitest/mock"
require "stringio"

class Distillator::P0TransitionSafetyTest < ActiveSupport::TestCase
  Cache = Struct.new(:uri_key, :normalized_url, :body, :html, :headers, :final_url, :redirect_chain,
    :http_response_code, :signals, :hints, :name, :scrape_date, :successful_refresh,
    :health_status, :network_status, :primary_issue_severity, :redirected, keyword_init: true) do
    def assign_attributes(attributes)
      attributes.each { |key, value| public_send("#{key}=", value) }
    end

    def save!; true; end
  end

  Evidence = Struct.new(:status, :checked_at, :details, keyword_init: true) do
    def detail_reason; details[:reason]; end
    def acceptable_statement_delta?; true; end
    def export_diff_checked; true; end
    def export_diff_accepted?; false; end
    def export_diff_satisfied?; true; end
  end

  test "warm native body is replaced before serving Legacy or Shadow" do
    %w[legacy shadow].each do |mode|
      cache = cache_for("native")
      result = fetch(cache, mode: mode, response: response("WRINGER", mode == "shadow" ? "shadow" : "legacy"))
      assert_not result.cache_hit
      assert_equal "WRINGER", result.body
      assert_equal "legacy", cache.signals.dig("body_profile", "backend")
    end
  end

  test "warm Legacy body is replaced before serving Active" do
    result = fetch(cache_for("legacy"), mode: "active", response: response("CONDENSER", "native"))
    assert_equal "CONDENSER", result.body
    assert_not result.cache_hit
  end

  test "failed rollback fetch cannot return the previous native body" do
    cache = cache_for("native")
    result = fetch(cache, mode: "legacy", response: failure_response)
    assert_nil result.html
    assert_nil cache.successful_refresh
    assert_not_equal "OLD", result.body
    assert_not result.content_success?
  end

  test "a matching body profile remains a cache hit" do
    cache = cache_for("legacy")
    result = fetch(cache, mode: "legacy", response: ->(**) { flunk "Matching cache must not fetch" })
    assert result.cache_hit
    assert_equal "OLD", result.body
  end

  test "historical rows without body provenance are refreshed once" do
    cache = cache_for("legacy")
    cache.signals.delete("body_profile")
    result = fetch(cache, mode: "legacy", response: response("NEW", "legacy"))
    assert_not result.cache_hit
    assert_equal "backend_profile_changed", result.cache_reason
  end

  test "request method rendering and rewriting changes invalidate body reuse" do
    [{ json_post: true }, { render_js: true }, { absolute_src: true }].each do |options|
      result = fetch(cache_for("native"), mode: "active", response: response("NEW", "native"), **options)
      assert_not result.cache_hit, options.inspect
    end
  end

  test "same profile failure still preserves the last good body and its provenance" do
    cache = cache_for("legacy")
    profile = cache.signals["body_profile"].dup
    result = fetch(cache, mode: "legacy", response: failure_response, force_scrape: true)
    assert_equal "OLD", result.body
    assert_equal profile, cache.signals["body_profile"]
    assert cache.signals["last_good_preserved_failure"]
    assert_not result.content_success?
  end

  test "blocking comparisons win over review regardless of URL order" do
    %w[review unknown missing].each do |other|
      [ [other, "failed"], ["failed", other] ].each do |statuses|
        status, details = aggregate(statuses)
        assert_equal :failed, status
        assert_equal "cache_compare_blocking_regression", details[:reason]
      end
    end
  end

  test "missing legacy lookup on another URL cannot hide a blocking comparison" do
    status, details = aggregate(["missing", "failed"], lookup: "unreachable")
    assert_equal :failed, status
    assert_equal "cache_compare_blocking_regression", details[:reason]
  end

  test "unknown and missing comparisons win over review" do
    %w[unknown missing].each do |other|
      status, = aggregate(["review", other])
      assert_equal :failed, status
    end
    status, = aggregate(["review", "passed"])
    assert_equal :checked, status
  end

  test "a newer cache failure blocks promotion despite fresh passing evidence" do
    result = readiness(attempt_offset: 1.hour, failed: true)
    assert_equal :blocked, result.status
    assert_equal :failed, result.fetch
    assert_equal :low, result.confidence
    assert_not result.review_activation_eligible
  end

  test "an older cache failure does not replace a newer passing validation" do
    assert_equal :ready, readiness(attempt_offset: -1.hour, failed: true).status
  end

  test "a newer healthy cache leaves passing evidence ready" do
    assert_equal :ready, readiness(attempt_offset: 1.hour, failed: false).status
  end

  private

  def cache_for(backend)
    Cache.new(uri_key: CGI.escape("https://example.org/event"), normalized_url: "https://example.org/event",
      body: "OLD", html: "OLD", headers: {}, redirect_chain: [], http_response_code: 200,
      signals: { "body_profile" => { "backend" => backend, "request_method" => "GET", "render_js" => false, "absolute_src" => false } },
      hints: [], name: "Event", scrape_date: Time.current, successful_refresh: Time.current)
  end

  def fetch(cache, mode:, response:, **options)
    Distillator::FetchCache.stub :find_by, cache do
      Distillator::FetchService.stub :fetch_result, response do
        Distillator::FetchCacheStore.fetch(uri: cache.normalized_url, mode: mode, logger: Logger.new(StringIO.new), **options)
      end
    end
  end

  def response(body, path)
    { status: :ok, body: body, raw_body: body, http_code: 200, headers: {}, fetch_path: path }
  end

  def failure_response
    { status: :abort, body: ["abort_update", { error: "unavailable" }], http_code: 503, fetch_path: "legacy",
      wringer: { signals: { transport_success: false, content_success: false, network_status: "failed" }, policy_action: "abort_update" } }
  end

  def aggregate(statuses, lookup: "ok")
    pages = statuses.each_index.map { |id| Struct.new(:url).new("https://example.org/#{id}") }
    check = Struct.new(:cache, :representative_webpages, :comparison_policy, :publishable_event_page_count,
      :candidate_webpage_count, :selected_candidate_tier_count, :selection_rule).new(cache_for("native"), pages, :operator, 2, 2, 2, "all")
    rows = statuses.each_with_index.map do |status, id|
      { url: pages[id].url, fetch_status: "passed", comparison_status: status,
        legacy_lookup_status: id.zero? ? lookup : "ok", cache: check.cache }
    end
    Distillator::TransitionCheckRunner.allocate.send(:fetch_check_payload, check, rows)
  end

  def readiness(attempt_offset:, failed:)
    checked_at = Time.current - 2.hours
    evidence = %w[fetch_parity statement_delta export_diff].to_h do |kind|
      [kind, Evidence.new(status: "checked", checked_at: checked_at, details: {})]
    end
    cache = cache_for("native")
    cache.scrape_date = checked_at + attempt_offset
    cache.signals = { "transport_success" => !failed, "content_success" => !failed }
    cache.health_status = failed ? "network_failed" : "healthy"
    cache.network_status = failed ? "failed" : "ok"
    website = Object.new
    def website.lavitrine_pipeline?; false; end
    Distillator::TransitionStatus.call(website: website, cache: cache, evidence_by_kind: evidence)
  end
end
