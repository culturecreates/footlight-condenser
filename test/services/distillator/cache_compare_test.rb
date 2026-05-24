require "test_helper"

class Distillator::CacheCompareTest < ActiveSupport::TestCase
  setup do
    Distillator::FetchCache.delete_all
  end

  test "handles injected lookup and missing cache cases" do
    key = CGI.escape("http://example.org/page")
    Distillator::FetchCache.create!(
      uri_key: key,
      normalized_url: "http://example.org/page",
      html: "<html>condenser</html>",
      body: "<html>condenser</html>",
      scrape_date: Time.zone.parse("2026-04-01 10:00:00"),
      successful_refresh: Time.zone.parse("2026-04-01 09:00:00"),
      http_response_code: 200,
      headers: {},
      signals: { "network_status" => "ok" },
      hints: [],
      final_url: "http://example.org/page",
      redirect_chain: []
    )

    both = Distillator::CacheCompare.call(
      uri: "http://example.org/page",
      legacy_lookup: ->(_uri_key) do
        {
          html: "<html>legacy</html>",
          scrape_date: "2026-04-01T10:00:00Z",
          successful_refresh: "2026-04-01T09:00:00Z",
          http_code: 200,
          signals: { network_status: "ok" },
          hints: [],
          final_url: "http://example.org/page",
          redirect_chain: []
        }
      end
    )
    assert_equal false, both.dig(:missing, :legacy)
    assert_equal false, both.dig(:missing, :condenser)
    assert_equal "injected_lookup", both[:legacy_source]
    assert_equal "ok", both[:legacy_lookup_status]
    assert_nil both[:legacy_lookup_error]
    assert_equal "local_fetch_cache", both[:condenser_source]
    assert_equal true, both.dig(:summary, :html_hash_difference)
    assert_includes both.dig(:summary, :blocking_regressions), :html_sha256

    legacy_missing = Distillator::CacheCompare.call(uri: "http://example.org/page", legacy_lookup: ->(_uri_key) { nil })
    assert_equal true, legacy_missing.dig(:missing, :legacy)
    assert_equal "injected_lookup", legacy_missing[:legacy_source]
    assert_equal false, legacy_missing.dig(:summary, :promotable)

    Distillator::FetchCache.delete_all
    distillator_missing = Distillator::CacheCompare.call(uri: "http://example.org/page", legacy_lookup: ->(_uri_key) { { html: "<html>legacy</html>" } })
    assert_equal true, distillator_missing.dig(:missing, :condenser)
    assert_equal false, distillator_missing.dig(:summary, :promotable)
  end

  test "labels successful remote wringer lookup" do
    endpoint = Distillator::WringerEndpoint::Result.new(
      compatibility_base_url: "http://compat.example",
      legacy_lookup_base_url: "http://wringer.example",
      state: :remote_configured,
      status_label: "Current Wringer: Remote configured",
      status_detail: "http://wringer.example"
    )
    HTTParty.stubs(:get).returns(Struct.new(:body).new([{ html: "<html>legacy</html>" }].to_json))

    result = Distillator::CacheCompare.call(uri: "http://example.org/page", wringer_endpoint: endpoint)

    assert_equal "remote_wringer", result[:legacy_source]
    assert_equal "ok", result[:legacy_lookup_status]
    assert_nil result[:legacy_lookup_error]
  end

  test "hydrates remote wringer html and title from compatibility endpoint when search payload omits body" do
    endpoint = Distillator::WringerEndpoint::Result.new(
      compatibility_base_url: "https://compat.example",
      legacy_lookup_base_url: "https://wringer.example",
      state: :remote_configured,
      status_label: "Current Wringer: Remote configured",
      status_detail: "https://wringer.example"
    )
    search_payload = [{
      "http_response_code" => 200,
      "successful_refresh" => "2026-03-06T16:47:36Z",
      "name" => "Legacy listing title"
    }]
    wring_payload = {
      "html" => "<html><title>Legacy hydrated title</title><body>cached</body></html>",
      "http_code" => 200,
      "successful_refresh" => "2026-03-06T16:47:36Z",
      "final_url" => "https://example.org/events/match-dimprovisation",
      "signals" => { "content_success" => true }
    }

    HTTParty.expects(:get).with(
      "https://wringer.example/websites.json",
      query: { term: CGI.escape("https://example.org/events/match-dimprovisation?lang=fr") }
    ).returns(Struct.new(:body).new(search_payload.to_json))
    HTTParty.expects(:get).with(
      "https://compat.example/websites/wring.json",
      query: { uri: "https://example.org/events/match-dimprovisation?lang=fr" }
    ).returns(Struct.new(:body).new(wring_payload.to_json))

    result = Distillator::CacheCompare.call(
      uri: "https://example.org/events/match-dimprovisation?lang=fr",
      wringer_endpoint: endpoint
    )

    assert_equal "ok", result[:legacy_lookup_status]
    assert_equal "<html><title>Legacy hydrated title</title><body>cached</body></html>", result.dig(:legacy_cache, :html)
    assert_equal "Legacy hydrated title", result.dig(:legacy_cache, :title)
    assert_equal false, result.dig(:missing, :legacy)
  end

  test "hydration request stays read only and sends only the normalized url query" do
    endpoint = Distillator::WringerEndpoint::Result.new(
      compatibility_base_url: "https://compat.example",
      legacy_lookup_base_url: "https://wringer.example",
      state: :remote_configured,
      status_label: "Current Wringer: Remote configured",
      status_detail: "https://wringer.example"
    )
    normalized_url = "https://example.org/evenements/cafe?lang=fr&ville=trois-rivieres"
    uri_key = CGI.escape(normalized_url)

    sequence = sequence("read_only_hydration")

    HTTParty.expects(:get).in_sequence(sequence).with(
      "https://wringer.example/websites.json",
      query: { term: uri_key }
    ).returns(Struct.new(:body).new([{ "http_response_code" => 200 }].to_json))
    HTTParty.expects(:get).in_sequence(sequence).with(
      "https://compat.example/websites/wring.json",
      query: { uri: normalized_url }
    ).returns(Struct.new(:body).new({ "html" => "<html><title>Hydrated</title></html>" }.to_json))

    result = Distillator::CacheCompare.call(uri: normalized_url, wringer_endpoint: endpoint)

    assert_equal "ok", result[:legacy_lookup_status]
    assert_equal "Hydrated", result.dig(:legacy_cache, :title)
  end

  test "hydration request ignores compare options and never sends legacy refresh flags" do
    endpoint = Distillator::WringerEndpoint::Result.new(
      compatibility_base_url: "https://compat.example",
      legacy_lookup_base_url: "https://wringer.example",
      state: :remote_configured,
      status_label: "Current Wringer: Remote configured",
      status_detail: "https://wringer.example"
    )
    normalized_url = "https://example.org/evenements/cafe?lang=fr"
    HTTParty.expects(:get).with(
      "https://wringer.example/websites.json",
      query: { term: CGI.escape(normalized_url) }
    ).returns(Struct.new(:body).new([{ "http_response_code" => 200 }].to_json))
    HTTParty.expects(:get).with(
      "https://compat.example/websites/wring.json",
      query: { uri: normalized_url }
    ).returns(Struct.new(:body).new({ "html" => "<html><title>Hydrated</title></html>" }.to_json))

    result = Distillator::CacheCompare.call(
      uri: normalized_url,
      include_fragment: true,
      wringer_endpoint: endpoint
    )

    assert_equal "ok", result[:legacy_lookup_status]
    assert_equal "Hydrated", result.dig(:legacy_cache, :title)
    assert_equal false, result.dig(:summary, :promotable)
  end

  test "keeps legacy row visible when wringer body endpoint omits html" do
    endpoint = Distillator::WringerEndpoint::Result.new(
      compatibility_base_url: "https://compat.example",
      legacy_lookup_base_url: "https://wringer.example",
      state: :remote_configured,
      status_label: "Current Wringer: Remote configured",
      status_detail: "https://wringer.example"
    )
    key = CGI.escape("https://example.org/events/body-omitted")
    fresh_cache = Distillator::FetchCache.create!(
      uri_key: key,
      normalized_url: "https://example.org/events/body-omitted",
      html: "<html><title>Condenser title</title><body>fresh</body></html>",
      body: "<html><title>Condenser title</title><body>fresh</body></html>",
      scrape_date: Time.zone.now,
      successful_refresh: Time.zone.now,
      http_response_code: 200,
      headers: {},
      signals: { "content_success" => true, "transport_success" => true },
      hints: [],
      final_url: "https://example.org/events/body-omitted/final",
      redirect_chain: []
    )
    HTTParty.stubs(:get).with("https://wringer.example/websites.json", query: { term: key }).returns(
      Struct.new(:body).new([{
        "http_response_code" => 200,
        "successful_refresh" => "2026-03-06T16:47:36Z",
        "final_url" => "https://example.org/events/body-omitted",
        "signals" => { "transport_success" => true }
      }].to_json)
    )
    HTTParty.stubs(:get).with("https://compat.example/websites/wring.json", query: { uri: "https://example.org/events/body-omitted" }).returns(
      Struct.new(:body).new({ "http_code" => 200, "successful_refresh" => "2026-03-06T16:47:36Z" }.to_json)
    )

    result = Distillator::CacheCompare.call(
      uri: "https://example.org/events/body-omitted",
      wringer_endpoint: endpoint
    )

    assert_equal "body_omitted", result[:legacy_lookup_status]
    assert_equal "legacy_body_omitted", result[:legacy_lookup_error]
    assert_equal false, result.dig(:missing, :legacy)
    assert_not_includes result.dig(:summary, :blocking_regressions), :html_sha256
    assert_not_includes result.dig(:summary, :blocking_regressions), :content_success
    assert_not_includes result.dig(:summary, :blocking_regressions), :final_url
    assert_includes result.dig(:summary, :unknown_diffs), :html_sha256
    assert_includes result.dig(:summary, :unknown_diffs), :content_success
    assert_includes result.dig(:summary, :unknown_diffs), :final_url
    assert_equal "<html><title>Condenser title</title><body>fresh</body></html>", fresh_cache.reload.html
    assert_equal false, result.dig(:summary, :promotable)
  end

  test "search uses uri_key once and hydration uses normalized url with encoded inputs" do
    endpoint = Distillator::WringerEndpoint::Result.new(
      compatibility_base_url: "https://compat.example",
      legacy_lookup_base_url: "https://wringer.example",
      state: :remote_configured,
      status_label: "Current Wringer: Remote configured",
      status_detail: "https://wringer.example"
    )
    raw_url = "https://example.org/evenements/caf%C3%A9?categorie=arts%20vivants&lang=fr"
    key = Distillator::WringerUrlKey.call(raw_url)

    HTTParty.expects(:get).with(
      "https://wringer.example/websites.json",
      query: { term: key.uri_key }
    ).returns(Struct.new(:body).new([{ "http_response_code" => 200 }].to_json))
    HTTParty.expects(:get).with(
      "https://compat.example/websites/wring.json",
      query: { uri: key.normalized_url }
    ).returns(Struct.new(:body).new({ "html" => "<html><title>Cafe</title></html>" }.to_json))

    result = Distillator::CacheCompare.call(uri: raw_url, wringer_endpoint: endpoint)

    assert_equal "ok", result[:legacy_lookup_status]
    assert_equal "Cafe", result.dig(:legacy_cache, :title)
  end

  test "labels failed remote wringer lookup without raising" do
    endpoint = Distillator::WringerEndpoint::Result.new(
      compatibility_base_url: "http://compat.example",
      legacy_lookup_base_url: "http://wringer.example",
      state: :remote_configured,
      status_label: "Current Wringer: Remote configured",
      status_detail: "http://wringer.example"
    )
    HTTParty.stubs(:get).raises(SocketError, "wringer unavailable")

    result = Distillator::CacheCompare.call(uri: "http://example.org/page", wringer_endpoint: endpoint)

    assert_equal "remote_wringer", result[:legacy_source]
    assert_equal "unreachable", result[:legacy_lookup_status]
    assert_match "wringer unavailable", result[:legacy_lookup_error]
    assert_equal true, result.dig(:missing, :legacy)
  end

  test "records missing config without attempting localhost" do
    endpoint = Distillator::WringerEndpoint::Result.new(
      compatibility_base_url: nil,
      legacy_lookup_base_url: nil,
      state: :missing_config,
      status_label: "Current Wringer: Missing staging config",
      status_detail: "comparisons disabled"
    )

    HTTParty.expects(:get).never

    result = Distillator::CacheCompare.call(uri: "http://example.org/page", wringer_endpoint: endpoint)

    assert_equal "missing_config", result[:legacy_source]
    assert_equal "missing_config", result[:legacy_lookup_status]
    assert_equal "missing_config", result[:legacy_lookup_error]
    assert_equal true, result.dig(:missing, :legacy)
  end

  test "uses the provided fresh condenser fetch result instead of reloading stale local cache" do
    key = CGI.escape("http://example.org/page")
    stale_cache = Distillator::FetchCache.create!(
      uri_key: key,
      normalized_url: "http://example.org/page",
      html: "<html>stale</html>",
      body: "<html>stale</html>",
      scrape_date: 2.days.ago,
      successful_refresh: 2.days.ago,
      http_response_code: 200,
      headers: {},
      signals: { "network_status" => "ok" },
      hints: [],
      final_url: "http://example.org/page",
      redirect_chain: []
    )
    fresh_cache = Distillator::FetchCache.new(
      uri_key: key,
      normalized_url: "http://example.org/page",
      html: "<html>fresh</html>",
      body: "<html>fresh</html>",
      scrape_date: Time.zone.now,
      successful_refresh: Time.zone.now,
      http_response_code: 200,
      headers: {},
      signals: { "network_status" => "ok" },
      hints: [],
      final_url: "http://example.org/page",
      redirect_chain: []
    )
    condenser_result = Distillator::FetchCacheStore::Result.new(
      status: :ok,
      body: "<html>fresh</html>",
      html: "<html>fresh</html>",
      headers: {},
      final_url: "http://example.org/page",
      redirect_chain: [],
      http_response_code: 200,
      signals: { "network_status" => "ok" },
      hints: [],
      duration_ms: 10,
      cache_hit: false,
      cache_write: true,
      cache_reason: "force_scrape",
      uri_key: key,
      normalized_url: "http://example.org/page",
      fetch_path: "native",
      name: "fresh",
      scrape_date: Time.zone.now,
      successful_refresh: Time.zone.now,
      cache: fresh_cache
    )

    result = Distillator::CacheCompare.call(
      uri: "http://example.org/page",
      condenser_result: condenser_result,
      legacy_lookup: ->(_uri_key) { { html: "<html>legacy</html>" } }
    )

    assert_equal "<html>fresh</html>", result.dig(:condenser_cache, :html)
    assert_equal "<html>stale</html>", stale_cache.reload.html
  end
end
