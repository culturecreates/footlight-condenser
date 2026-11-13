require "test_helper"

class Distillator::FreshWringerSnapshotTest < ActiveSupport::TestCase
  include WebMock::API
  setup do
    WebMock.reset!
    @url = "https://example.org/event"
    @endpoint = Distillator::WringerEndpoint::Result.new(legacy_lookup_base_url: "https://legacy.example",
      compatibility_base_url: "https://condenser.example")
  end

  test "forces a new scrape on the explicit legacy backend without cache lookup" do
    request = fresh_request.to_return(status: 200, body: { html: "<title>Updated</title>", http_code: 200 }.to_json)
    result = fetch
    assert_equal "ok", result[:status]
    assert_equal "remote_wringer_fresh", result[:source]
    assert_equal "<title>Updated</title>", result[:payload]["html"]
    assert result[:fetch][:requested_at]
    assert result[:fetch][:received_at]
    assert_equal true, result[:fetch][:force_scrape]
    assert_requested request, times: 1
    assert_not_requested :get, "https://legacy.example/websites.json"
    assert_not_requested :get, "https://condenser.example/websites/wring.json"
  end

  test "rendered and fragment options are explicit only when enabled" do
    request = stub_request(:get, "https://legacy.example/websites/wring.json")
      .with(query: { uri: @url, force_scrape: "true", use_phantomjs: "true", include_fragment: "true" })
      .to_return(body: { html: "rendered", http_code: 200 }.to_json)
    assert_equal "ok", fetch(render_js: true, include_fragment: true)[:status]
    assert_requested request, times: 1
  end

  test "rejects last good HTML on upstream HTTP failure or missing status" do
    [503, 404, nil].each do |code|
      fresh_request.to_return(body: { html: "old cached HTML", http_code: code }.to_json)
      result = fetch
      assert_equal "unreachable", result[:status]
      assert_nil result[:payload]
      assert_includes result[:error], "cached HTML rejected"
    end
  end

  test "rejects unsuccessful service HTTP response even with a successful looking body" do
    fresh_request.to_return(status: 500, body: { html: "old cached HTML", http_code: 200 }.to_json)
    assert_nil fetch[:payload]
    assert_equal "unreachable", fetch[:status]
  end

  test "rejects explicit failed scrape signals and abort policy" do
    [{ network_status: "failed" }, { content_success: false }, { transport_success: "false" },
      { blocking_issue_key: "captcha_detected" }, { cache: "abort_update" }].each do |signals|
      fresh_request.to_return(body: { html: "old cached HTML", http_code: 200, signals: signals }.to_json)
      result = fetch
      assert_equal "unreachable", result[:status]
      assert_nil result[:payload]
    end
  end

  test "empty body malformed JSON and timeout never fall back to a cache listing" do
    fresh_request.to_return(body: { html: "", http_code: 200 }.to_json)
    assert_equal "body_omitted", fetch[:status]
    fresh_request.to_return(body: "not JSON")
    assert_equal "unreachable", fetch[:status]
    fresh_request.to_timeout
    assert_equal "unreachable", fetch[:status]
    assert_not_requested :get, "https://legacy.example/websites.json"
  end

  test "requires a configured legacy endpoint" do
    @endpoint.legacy_lookup_base_url = nil
    assert_equal "missing_config", fetch[:status]
  end

  private

  def fresh_request
    stub_request(:get, "https://legacy.example/websites/wring.json").with(query: { uri: @url, force_scrape: "true" })
  end

  def fetch(**options)
    Distillator::FreshWringerSnapshot.call(uri: @url, wringer_endpoint: @endpoint, **options)
  end
end
