require "test_helper"

class Distillator::FetchEligibilityTest < ActiveSupport::TestCase
  test "eligible for rendered fetch when render_js is true" do
    result = Distillator::FetchEligibility.call(
      url: "https://example.com/events",
      render_js: true,
      scrape_options: {}
    )

    assert_equal true, result.eligible?
    assert_equal :rendered_fetch, result.reason
  end

  test "eligible for native http post when json_post is true" do
    result = Distillator::FetchEligibility.call(
      url: "https://example.com/events",
      render_js: false,
      scrape_options: { json_post: true }
    )

    assert_equal true, result.eligible?
    assert_equal :native_http_post, result.reason
  end

  test "ineligible for non-http scheme" do
    result = Distillator::FetchEligibility.call(
      url: "ftp://example.com/events",
      render_js: false,
      scrape_options: {}
    )

    assert_equal false, result.eligible?
    assert_equal :unsupported_scheme, result.reason
    assert_equal true, result.abort?
  end

  test "ineligible for blocked url" do
    result = Distillator::FetchEligibility.call(
      url: "http://127.0.0.1/events",
      render_js: false,
      scrape_options: {}
    )

    assert_equal false, result.eligible?
    assert_equal :blocked_url, result.reason
    assert_equal true, result.abort?
    assert_match(/blocked/i, result.details[:guard_error])
  end

  test "ineligible when force legacy is set" do
    result = Distillator::FetchEligibility.call(
      url: "https://example.com/events",
      render_js: false,
      scrape_options: { force_legacy: true }
    )

    assert_equal false, result.eligible?
    assert_equal :forced_legacy, result.reason
    assert_equal true, result.legacy_fallback?
  end

  test "string false force_legacy does not force legacy" do
    result = Distillator::FetchEligibility.call(
      url: "https://example.com/events",
      render_js: "false",
      scrape_options: { force_legacy: "false" }
    )

    assert_equal true, result.eligible?
    assert_equal :native_http_get, result.reason
    assert_equal false, result.details[:forced_legacy]
    assert_equal false, result.details[:render_js]
  end

  test "string true render_js is reflected in details" do
    result = Distillator::FetchEligibility.call(
      url: "https://example.com/events",
      render_js: "true",
      scrape_options: {}
    )

    assert_equal true, result.eligible?
    assert_equal :rendered_fetch, result.reason
    assert_equal true, result.details[:render_js]
  end

  test "eligible for ordinary http get" do
    result = Distillator::FetchEligibility.call(
      url: "https://example.com/events",
      render_js: false,
      scrape_options: {}
    )

    assert_equal true, result.eligible?
    assert_equal :native_http_get, result.reason
  end
end
