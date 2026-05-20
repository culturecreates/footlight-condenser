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
    ApplicationController.helpers.stubs(:get_wringer_url_per_environment).returns("http://wringer.example")
    HTTParty.stubs(:get).returns(Struct.new(:body).new([{ html: "<html>legacy</html>" }].to_json))

    result = Distillator::CacheCompare.call(uri: "http://example.org/page")

    assert_equal "remote_wringer", result[:legacy_source]
    assert_nil result[:legacy_lookup_error]
  end

  test "labels failed remote wringer lookup without raising" do
    ApplicationController.helpers.stubs(:get_wringer_url_per_environment).returns("http://wringer.example")
    HTTParty.stubs(:get).raises(SocketError, "wringer unavailable")

    result = Distillator::CacheCompare.call(uri: "http://example.org/page")

    assert_equal "unavailable", result[:legacy_source]
    assert_match "wringer unavailable", result[:legacy_lookup_error]
    assert_equal true, result.dig(:missing, :legacy)
  end
end
