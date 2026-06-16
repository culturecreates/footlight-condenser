require "test_helper"

class Distillator::PhantomjsFetcherTest < ActiveSupport::TestCase
  setup do
    @old_phantomjs_api_key = ENV["PHANTOMJS_API_KEY"]
    @old_direct_fallback = ENV["DISTILLATOR_ALLOW_RENDERED_DIRECT_FALLBACK"]
  end

  teardown do
    ENV["PHANTOMJS_API_KEY"] = @old_phantomjs_api_key
    ENV["DISTILLATOR_ALLOW_RENDERED_DIRECT_FALLBACK"] = @old_direct_fallback
  end

  test "missing phantomjs api key returns renderer unavailable abort by default" do
    ENV["PHANTOMJS_API_KEY"] = nil
    ENV["DISTILLATOR_ALLOW_RENDERED_DIRECT_FALLBACK"] = nil
    Distillator::NativeFetch.expects(:call).never

    result = Distillator::PhantomjsFetcher.call(
      url: "https://www.ovation.ca/event",
      uri_key: CGI.escape("https://www.ovation.ca/event"),
      iframe: false
    )

    assert_equal :abort, result[:status]
    assert_equal true, result.dig(:wringer, :signals, :renderer_unavailable)
    assert_equal "none", result.dig(:wringer, :signals, :renderer_fallback)
    assert_includes result.dig(:wringer, :hints), "phantomjs_unavailable"
  end
end
