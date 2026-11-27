require "test_helper"

class Distillator::Renderers::LegacyPhantomjsRendererTest < ActiveSupport::TestCase
  setup do
    @old_api_key = ENV["PHANTOMJS_API_KEY"]
  end

  teardown do
    ENV["PHANTOMJS_API_KEY"] = @old_api_key
  end

  test "builds wringer-compatible phantomjs request url" do
    ENV["PHANTOMJS_API_KEY"] = "secret"

    url = Distillator::Renderers::LegacyPhantomjsRenderer.request_url(url: "https://example.com/page", iframe: true)

    assert_equal(
      "https://phantomjscloud.com/api/browser/v2/secret/?request={url:%22https://example.com/page%22,renderType:%22html%22,outputAsJson:true,requestSettings:{ignoreImages:true, waitInterval:2500 }}",
      url
    )
  end

  test "extracts first child iframe html from phantomjs json payload" do
    ENV["PHANTOMJS_API_KEY"] = "secret"
    Distillator::NativeFetch.expects(:call).returns(
      status: :ok,
      body: '{"pageResponses":[{"frameData":{"childFrames":[{"content":"<html>iframe child</html>"}]}}]}',
      headers: { content_type: "application/json" },
      final_url: "https://phantomjscloud.com/api/browser/v2/secret",
      redirect_chain: [],
      wringer: { signals: {}, hints: [] },
      http_code: 200,
      raw_body: '{"pageResponses":[{"frameData":{"childFrames":[{"content":"<html>iframe child</html>"}]}}]}'
    )

    result = Distillator::Renderers::LegacyPhantomjsRenderer.call(
      url: "https://example.com/iframe",
      uri_key: CGI.escape("https://example.com/iframe"),
      iframe: true
    )

    assert_equal "<html>iframe child</html>", result[:body]
    assert_equal "<html>iframe child</html>", result[:raw_body]
    assert_equal "https://example.com/iframe", result[:final_url]
    assert_equal "legacy_phantomjs", result.dig(:wringer, :signals, :renderer)
  end

  test "missing phantomjs api key returns renderer unavailable abort by default" do
    ENV["PHANTOMJS_API_KEY"] = nil
    Distillator::NativeFetch.expects(:call).never

    result = Distillator::Renderers::LegacyPhantomjsRenderer.call(
      url: "https://example.com/page",
      uri_key: CGI.escape("https://example.com/page"),
      iframe: false
    )

    assert_equal :abort, result[:status]
    assert_equal "abort_update", result[:body].first
    assert_equal "DistillatorRendererUnavailable", result[:body].last[:error_type]
    assert_equal false, result.dig(:wringer, :cache)
    assert_equal true, result.dig(:wringer, :retry)
    assert_equal "legacy_phantomjs", result.dig(:wringer, :signals, :renderer)
    assert_equal true, result.dig(:wringer, :signals, :renderer_unavailable)
    assert_equal "none", result.dig(:wringer, :signals, :renderer_fallback)
  end
end
