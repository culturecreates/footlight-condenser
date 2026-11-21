require "test_helper"

class Distillator::HtmlAbsolutizerTest < ActiveSupport::TestCase
  test "call rewrites root relative src" do
    html = '<img src="/image.png">'

    rewritten = Distillator::HtmlAbsolutizer.call(html: html, base_url: "https://example.com/artist/")

    assert_includes rewritten, 'src="https://example.com/image.png"'
  end

  test "call leaves absolute urls unchanged" do
    html = '<img src="http://another.com/image.png">'

    rewritten = Distillator::HtmlAbsolutizer.call(html: html, base_url: "https://example.com/artist/")

    assert_includes rewritten, 'src="http://another.com/image.png"'
  end

  test "call rewrites parent relative paths and preserves sibling attributes" do
    html = '<img src="../image.png" width="100px">'

    rewritten = Distillator::HtmlAbsolutizer.call(html: html, base_url: "https://example.com/artist/")

    assert_includes rewritten, 'src="https://example.com/image.png"'
    assert_includes rewritten, 'width="100px"'
  end

  test "call preserves malformed paths without raising" do
    html = '<img src="not a path" width="100px"><a href="/path">path</a>'

    rewritten = Distillator::HtmlAbsolutizer.call(html: html, base_url: "https://example.com/artist/")

    assert_includes rewritten, 'src="not a path"'
    assert_includes rewritten, 'href="https://example.com/path"'
    assert_includes rewritten, 'width="100px"'
  end
end
