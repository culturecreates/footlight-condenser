require "test_helper"

class Distillator::QaFetchIsolationTest < ActiveSupport::TestCase
  # Related records are built explicitly; no legacy fixture loading.
  self.fixture_table_names = []

  setup do
    @original = Website.create!(name: "Original calendar", seedurl: "qa-cache-original-ca",
      graph_name: "https://example.org/original", default_language: "en")
    @copy = Website.create!(name: "QA calendar", seedurl: "qa-cache-copy-ca",
      graph_name: "https://example.org/qa", default_language: "en",
      test_copy_of_website: @original, distillator_mode: "shadow")
    @other_copy = Website.create!(name: "Second QA calendar", seedurl: "qa-cache-other-ca",
      graph_name: "https://example.org/qa2", default_language: "en",
      test_copy_of_website: @original, distillator_mode: "shadow")
    @url = "https://example.org/events?page=1"
  end

  test "original and copied site cache the same public URL independently" do
    Distillator::FetchService.expects(:fetch_result).twice
      .returns(response("Original HTML"), response("QA HTML"))
    original = Distillator::FetchCacheStore.fetch(uri: @url, mode: :active, website: @original)
    qa = Distillator::FetchCacheStore.fetch(uri: @url, website: @copy)
    assert_equal "Original HTML", original.body
    assert_equal "QA HTML", qa.body
    assert_equal Distillator::WringerUrlKey.call(@url).uri_key, original.uri_key
    assert_match(/\Aqa:#{@copy.id}:[0-9a-f]{64}\z/, qa.uri_key)
    assert_not_equal original.uri_key, qa.uri_key
    assert_equal "Original HTML", Distillator::FetchCache.find_by!(uri_key: original.uri_key).body
    assert_equal "QA HTML", Distillator::FetchCache.find_by!(uri_key: qa.uri_key).body

    # Cached subsequent accesses do not invoke FetchService again.
    assert_equal "Original HTML", Distillator::FetchCacheStore.fetch(uri: @url, mode: :active, website: @original).body
    assert_equal "QA HTML", Distillator::FetchCacheStore.fetch(uri: @url, website: @copy).body
  end

  test "refreshing either side does not mutate the other side" do
    Distillator::FetchService.expects(:fetch_result).times(4)
      .returns(response("Original 1"), response("QA 1"), response("Original 2"), response("QA 2"))
    original = Distillator::FetchCacheStore.fetch(uri: @url, mode: :active, website: @original)
    qa = Distillator::FetchCacheStore.fetch(uri: @url, website: @copy)
    Distillator::FetchCacheStore.fetch(uri: @url, mode: :active, website: @original, force_scrape: true)
    assert_equal "QA 1", Distillator::FetchCache.find_by!(uri_key: qa.uri_key).body
    assert_equal "Original 2", Distillator::FetchCache.find_by!(uri_key: original.uri_key).body
    Distillator::FetchCacheStore.fetch(uri: @url, website: @copy, force_scrape: true)
    assert_equal "Original 2", Distillator::FetchCache.find_by!(uri_key: original.uri_key).body
    assert_equal "QA 2", Distillator::FetchCache.find_by!(uri_key: qa.uri_key).body
  end

  test "QA website identity is found via website ID or fetch context" do
    expected = Distillator::QaFetchIsolation.cache_key(
      uri_key: Distillator::WringerUrlKey.call(@url).uri_key, website_id: @copy.id)
    Distillator::FetchService.expects(:fetch_result).once.returns(response("QA HTML"))
    first = Distillator::FetchCacheStore.fetch(uri: @url, website_id: @copy.id)
    second = Distillator::FetchCacheStore.fetch(uri: @url, log_context: { website_id: @copy.id })
    assert_equal expected, first.uri_key
    assert_equal expected, second.uri_key
    assert_equal "QA HTML", second.body
  end

  test "different QA websites do not share a cached body" do
    Distillator::FetchService.expects(:fetch_result).twice
      .returns(response("QA A"), response("QA B"))
    a = Distillator::FetchCacheStore.fetch(uri: @url, website: @copy)
    b = Distillator::FetchCacheStore.fetch(uri: @url, website: @other_copy)
    assert_not_equal a.uri_key, b.uri_key
    assert_equal "QA A", a.body
    assert_equal "QA B", b.body
  end

  test "QA fetch cannot fall back to Wringer even when its rollout mode is shadow" do
    eligible = Struct.new(:eligible?, :details).new(true, {})
    Distillator::FetchService.stubs(:fetch_eligibility).returns(eligible)
    Distillator::FetchService.expects(:legacy_fetch).never
    Distillator::FetchService.expects(:guarded_internal_fetch).once.returns(response("Native QA"))
    result = Distillator::FetchService.fetch_result(url: @url, website: @copy)
    assert_equal "Native QA", result[:body]
    assert_equal "native", result[:fetch_path]
  end

  test "QA fetch with an explicit legacy client fails closed" do
    Distillator::FetchService.expects(:legacy_fetch).never
    Distillator::FetchService.expects(:guarded_internal_fetch).never
    client = mock("legacy client")
    result = Distillator::FetchService.fetch_result(url: @url, website: @copy, client: client)
    assert_equal :abort, result[:status]
    assert_equal "blocked", result[:fetch_path]
    assert_raises(ArgumentError) do
      Distillator::FetchCacheStore.fetch(uri: @url, website: @copy, client: client)
    end
  end

  private

  def response(html)
    {
      status: :ok, body: html, raw_body: html,
      headers: { content_type: "text/html" },
      final_url: @url, redirect_chain: [], fetch_path: "native",
      wringer: { signals: { network_status: "ok", content_type: "html" }, hints: [] },
      http_code: 200, duration_ms: 1
    }
  end
end
