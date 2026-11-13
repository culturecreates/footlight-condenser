require "test_helper"

class Distillator::FetchCacheCompatSerializerTest < ActiveSupport::TestCase
  test "serializes compatibility payload with normalized nil collections" do
    cache = Struct.new(
      :id,
      :uri_key,
      :normalized_url,
      :html,
      :body,
      :name,
      :scrape_date,
      :successful_refresh,
      :http_response_code,
      :signals,
      :hints,
      :final_url,
      :redirect_chain,
      :created_at,
      :updated_at,
      keyword_init: true
    ).new(
      id: 123,
      uri_key: "http%3A%2F%2Fexample.org%2Fcached",
      normalized_url: "http://example.org/cached",
      html: "<html>cached</html>",
      body: "<html>cached</html>",
      name: "Cached",
      scrape_date: Time.zone.now,
      successful_refresh: Time.zone.now,
      http_response_code: 200,
      signals: {
        "network_status" => "ok",
        "content_type" => "html",
        "redirect_type" => "normal",
        "fetch_path" => "legacy",
        "native_ineligible_reason" => "json_post"
      },
      hints: nil,
      final_url: "https://example.org/final",
      redirect_chain: nil,
      created_at: Time.zone.now,
      updated_at: Time.zone.now
    )

    payload = Distillator::FetchCacheCompatSerializer.new(cache).as_json

    assert_equal cache.id, payload[:id]
    assert_equal cache.uri_key, payload[:uri]
    assert_equal cache.uri_key, payload[:uri_key]
    assert_equal "http://example.org/cached", payload[:normalized_url]
    assert_equal "Cached", payload[:name]
    assert_equal true, payload[:has_html]
    assert_equal "<html>cached</html>".bytesize, payload[:html_bytes]
    assert_equal "<html>cached</html>".bytesize, payload[:body_bytes]
    assert_equal "ok", payload[:network_status]
    assert_equal "html", payload[:content_type]
    assert_equal "normal", payload[:redirect_type]
    assert_equal "legacy", payload[:fetch_path]
    assert_equal "json_post", payload[:native_ineligible_reason]
    assert_equal [], payload[:hints]
    assert_equal [], payload[:redirect_chain]
    assert_equal "healthy", payload[:health_status]
    assert_equal "Healthy", payload[:health_label]
  end
end
