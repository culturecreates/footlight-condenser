require "test_helper"

class Distillator::RenderedFetchTest < ActiveSupport::TestCase
  setup do
    @old_renderer = ENV["DISTILLATOR_RENDERER"]
  end

  teardown do
    ENV["DISTILLATOR_RENDERER"] = @old_renderer
  end

  test "uses legacy phantomjs renderer by default" do
    ENV["DISTILLATOR_RENDERER"] = nil
    Distillator::PhantomjsFetcher.expects(:call).with(has_entries(url: "https://example.com/page", iframe: false)).returns(status: :ok)

    result = Distillator::RenderedFetch.call(url: "https://example.com/page", uri_key: CGI.escape("https://example.com/page"))

    assert_equal :ok, result[:status]
  end

  test "uses disabled renderer when configured" do
    ENV["DISTILLATOR_RENDERER"] = "disabled"
    Distillator::Renderers::DisabledRenderer.expects(:call).with(has_entries(url: "https://example.com/page", iframe: true)).returns(status: :abort)

    result = Distillator::RenderedFetch.call(
      url: "https://example.com/page",
      uri_key: CGI.escape("https://example.com/page"),
      iframe: true
    )

    assert_equal :abort, result[:status]
  end
end
