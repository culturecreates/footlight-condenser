require "test_helper"

class Distillator::HtmlRewriterTest < ActiveSupport::TestCase
  test "absolute_src rewrites relative href and src attributes" do
    html = <<~HTML.squish
      <a href="../events">events</a>
      <img src="/image.png">
      <script src="assets/app.js"></script>
      <link href="styles/site.css" rel="stylesheet">
    HTML

    rewritten = Distillator::HtmlRewriter.absolute_src(html, "http://example.com/artist/")

    assert_includes rewritten, 'href="http://example.com/events"'
    assert_includes rewritten, 'src="http://example.com/image.png"'
    assert_includes rewritten, 'src="http://example.com/artist/assets/app.js"'
    assert_includes rewritten, 'href="http://example.com/artist/styles/site.css"'
  end

  test "absolute_src rewrites root relative src and leaves absolute urls unchanged" do
    html = <<~HTML.squish
      <img src="/image.png">
      <a href="events/opening-night">opening night</a>
      <img src="https://cdn.example.org/poster.jpg">
      <a href="https://tickets.example.org/show">tickets</a>
    HTML

    rewritten = Distillator::HtmlRewriter.absolute_src(html, "https://example.com/artist/")

    assert_includes rewritten, 'src="https://example.com/image.png"'
    assert_includes rewritten, 'href="https://example.com/artist/events/opening-night"'
    assert_includes rewritten, 'src="https://cdn.example.org/poster.jpg"'
    assert_includes rewritten, 'href="https://tickets.example.org/show"'
  end

  test "absolute_src preserves invalid src values without absolutizing them" do
    html = '<img src="not a path" width="100px">'

    rewritten = Distillator::HtmlRewriter.absolute_src(html, "http://example.com/artist/")

    assert_includes rewritten, 'src="not a path"'
    assert_includes rewritten, 'width="100px"'
    assert_not_includes rewritten, 'http://example.com'
  end

  test "absolute_src normalizes protocol relative URLs using page scheme" do
    html = '<img src="//cdn.example.org/image.png"><script src="//cdn.example.org/app.js"></script>'

    rewritten = Distillator::HtmlRewriter.absolute_src(html, "https://example.com/artist/")

    assert_includes rewritten, 'src="https://cdn.example.org/image.png"'
    assert_includes rewritten, 'src="https://cdn.example.org/app.js"'
  end

  test "absolute_src preserves anchor mailto tel and data values" do
    html = <<~HTML.squish
      <a href="#bio">bio</a>
      <a href="mailto:boxoffice@example.org">mail</a>
      <a href="tel:+14165551234">call</a>
      <img src="data:image/png;base64,AAAA">
    HTML

    rewritten = Distillator::HtmlRewriter.absolute_src(html, "https://example.com/artist/")

    assert_includes rewritten, 'href="#bio"'
    assert_includes rewritten, 'href="mailto:boxoffice@example.org"'
    assert_includes rewritten, 'href="tel:+14165551234"'
    assert_includes rewritten, 'src="data:image/png;base64,AAAA"'
  end

  test "absolute_src respects base href when present" do
    html = <<~HTML.squish
      <base href="https://cdn.example.org/site/">
      <img src="images/poster.jpg">
      <a href="../events/opening-night">opening night</a>
    HTML

    rewritten = Distillator::HtmlRewriter.absolute_src(html, "https://example.com/artist/")

    assert_includes rewritten, 'src="https://cdn.example.org/site/images/poster.jpg"'
    assert_includes rewritten, 'href="https://cdn.example.org/events/opening-night"'
    assert_includes rewritten, '<base href="https://cdn.example.org/site/">'
  end

  test "absolute_src does not raise on malformed HTML" do
    html = '<div><img src="/poster.jpg"><a href="../events">Open'

    rewritten = Distillator::HtmlRewriter.absolute_src(html, "https://example.com/artist/")

    assert_includes rewritten, 'src="https://example.com/poster.jpg"'
    assert_includes rewritten, 'href="https://example.com/events"'
  end

  test "absolute_src preserves malformed paths without raising" do
    html = <<~HTML.squish
      <img src="http://[broken">
      <a href="%%%">
    HTML

    rewritten = Distillator::HtmlRewriter.absolute_src(html, "https://example.com/artist/")

    assert_includes rewritten, 'src="http://[broken"'
    assert_includes rewritten, 'href="%%%"'
  end
end
