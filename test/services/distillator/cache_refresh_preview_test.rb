require "test_helper"

class Distillator::CacheRefreshPreviewTest < ActiveSupport::TestCase
  setup do
    Distillator::FetchCache.delete_all
  end

  test "missing cache returns would_refresh true with missing_cache" do
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    preview = Distillator::CacheRefreshPreview.call(uri: "http://example.org/missing")

    assert_equal true, preview[:would_refresh]
    assert_equal :missing_cache, preview[:reason]
    assert_equal false, preview[:cache_exists]
  end

  test "nil scrape_date returns missing_scrape_date" do
    cache = create_cache(scrape_date: nil)
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    preview = Distillator::CacheRefreshPreview.call(uri: cache.normalized_url)

    assert_equal true, preview[:would_refresh]
    assert_equal :missing_scrape_date, preview[:reason]
    assert_equal cache.id, preview[:cache_id]
  end

  test "force_scrape true returns force_scrape" do
    cache = create_cache(scrape_date: 1.minute.ago)
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    preview = Distillator::CacheRefreshPreview.call(uri: cache.normalized_url, force_scrape: true)

    assert_equal true, preview[:would_refresh]
    assert_equal :force_scrape, preview[:reason]
  end

  test "stale cache returns stale_by_force_scrape_every_hrs" do
    cache = create_cache(scrape_date: 2.days.ago)
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    preview = Distillator::CacheRefreshPreview.call(uri: cache.normalized_url, force_scrape_every_hrs: "24")

    assert_equal true, preview[:would_refresh]
    assert_equal :stale_by_force_scrape_every_hrs, preview[:reason]
  end

  test "force_scrape_every_hrs zero returns refresh required" do
    cache = create_cache(scrape_date: 1.minute.ago)
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    preview = Distillator::CacheRefreshPreview.call(uri: cache.normalized_url, force_scrape_every_hrs: "0")

    assert_equal true, preview[:would_refresh]
    assert_equal :stale_by_force_scrape_every_hrs, preview[:reason]
  end

  test "fresh cache returns fresh_cache" do
    cache = create_cache(scrape_date: 1.minute.ago)
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))

    preview = Distillator::CacheRefreshPreview.call(uri: cache.normalized_url, force_scrape_every_hrs: "200000")

    assert_equal false, preview[:would_refresh]
    assert_equal :fresh_cache, preview[:reason]
  end

  test "invalid uri returns invalid_uri" do
    preview = Distillator::CacheRefreshPreview.call(uri: "http://[invalid")

    assert_equal false, preview[:would_refresh]
    assert_equal :invalid_uri, preview[:reason]
    assert_nil preview[:uri_key]
  end

  test "blank uri returns invalid_uri" do
    preview = Distillator::CacheRefreshPreview.call(uri: "")

    assert_equal false, preview[:would_refresh]
    assert_equal :invalid_uri, preview[:reason]
    assert_nil preview[:uri_key]
  end

  test "blocked url returns blocked_url" do
    Distillator::FetchGuard.stubs(:check_url).returns(
      Distillator::FetchGuard::Result.new(
        allowed: false,
        error: "Blocked URL host after DNS resolution error for timeout.example: Timeout::Error",
        reason: :dns_resolution_error
      )
    )

    preview = Distillator::CacheRefreshPreview.call(uri: "http://127.0.0.1")

    assert_equal false, preview[:would_refresh]
    assert_equal :blocked_url, preview[:reason]
    assert_equal :dns_resolution_error, preview[:guard_reason]
    assert_includes preview[:guard_error], "Timeout::Error"
  end

  private

  def create_cache(scrape_date:)
    Distillator::FetchCache.create!(
      uri_key: CGI.escape("http://example.org/cached"),
      normalized_url: "http://example.org/cached",
      html: "<html>cached</html>",
      body: "<html>cached</html>",
      scrape_date: scrape_date,
      successful_refresh: Time.zone.now,
      http_response_code: 200,
      headers: {},
      signals: {},
      hints: [],
      redirect_chain: []
    )
  end
end
