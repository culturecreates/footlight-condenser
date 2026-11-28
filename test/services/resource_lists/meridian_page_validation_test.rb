require "test_helper"

class ResourceLists::MeridianPageValidationTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "legitimate bilingual calendar can use a venue title without the word events" do
    html = <<~HTML
      <html><head><title>Meridian Theatres @ Centrepointe</title></head><body>
      <header><nav><a href="/en">Home</a><a href="/en/events">Schedule</a></nav></header>
      <main><h1>2026 Season</h1>
      <a href="/en/event/a">A</a><a href="/en/event/b">B</a>
      <a href="/en/event/c">C</a><a href="/en/event/d">D</a></main><footer>Contact</footer>
      </body></html>
    HTML
    result = ResourceLists::MeridianPageValidation.call(html: html)
    assert_equal "Meridian Theatres @ Centrepointe", result.title
    assert_equal "observed", result.page_evidence["page_validation_status"]
  end

  test "HTTP 200 interstitial is rejected without invoking the event XPath" do
    html = <<~HTML
      <!doctype html><html><head><title>Pardon Our Interruption</title>
      <meta name="robots" content="noindex,nofollow"></head>
      <body><h1>Pardon Our Interruption</h1><p>We thought you were a bot.</p>
      <p>To regain access, make sure that cookies and JavaScript are enabled.</p></body></html>
    HTML
    error = assert_raises(ResourceLists::MeridianPageValidation::Invalid) do
      ResourceLists::MeridianPageValidation.call(html: html)
    end
    assert_match(/Content rejected/, error.message)
  end

  test "HTTP 200 error shell with a plausible title and no links is not a trusted calendar" do
    html = "<html><head><title>Calendar</title></head><body><h1>Schedule</h1><p>Check back later</p></body></html>"
    error = assert_raises(ResourceLists::MeridianPageValidation::Invalid) do
      ResourceLists::MeridianPageValidation.call(html: html)
    end
    assert_match(/navigation\/link structure/, error.message)
  end

  test "missing head title is unverified even if navigation is present" do
    html = '<html><body><nav><a href="/1">1</a><a href="/2">2</a><a href="/3">3</a><a href="/4">4</a><a href="/5">5</a></nav></body></html>'
    error = assert_raises(ResourceLists::MeridianPageValidation::Invalid) do
      ResourceLists::MeridianPageValidation.call(html: html)
    end
    assert_equal "Missing HTML page title", error.message
  end
end
