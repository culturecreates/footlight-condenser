require "test_helper"

class ResourceLists::MeridianRenderedPageTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  URL = "https://meridiancentrepointe.com/fr/evenements?page=1"
  VALID_HTML = <<~HTML.freeze
    <html><head><title>Meridian Theatres | Événements</title></head><body>
    <nav><a href="/fr/">Accueil</a><a href="/fr/evenements">Événements</a></nav>
    <main><h1>Événements à venir</h1><a href="/fr/a">A</a><a href="/fr/b">B</a><a href="/fr/c">C</a></main>
    <footer>Contact</footer></body></html>
  HTML

  def result(body: VALID_HTML, path: "native", backend: "phantomjs", rendered: true,
    final_url: URL, success: true, status: :ok, http: 200)
    { status: status, body: body, raw_body: body, http_code: http, final_url: final_url,
      fetch_path: path, headers: { content_type: "text/html" },
      wringer: { signals: { content_success: success, use_phantomjs: rendered,
        fetch_backend: backend }, hints: [] } }
  end

  test "fetches through native rendering and returns an auditable HTML receipt" do
    Distillator::FetchService.expects(:fetch_result).with do |options|
      assert_equal URL, options[:url]
      assert_equal true, options[:render_js]
      assert_equal :internal, options[:mode]
      assert_equal({}, options[:scrape_options])
    end.returns(result)
    receipt = ResourceLists::MeridianRenderedPage.call(url: URL)
    assert_equal "rendered_native", receipt[:capture_mode]
    assert_equal "native", receipt[:fetch_path]
    assert_equal "phantomjs", receipt[:fetch_backend]
    assert_equal VALID_HTML, receipt[:html]
    assert_equal Digest::SHA256.hexdigest(VALID_HTML), receipt[:sha256]
  end

  test "refuses HTTP 200 content from a non-rendered backend" do
    Distillator::FetchService.expects(:fetch_result).returns(result(rendered: false, backend: "native"))
    error = assert_raises(ResourceLists::MeridianRenderedPage::Invalid) { ResourceLists::MeridianRenderedPage.call(url: URL) }
    assert_match(/did not confirm rendered content/, error.message)
  end

  test "refuses successful responses that fell back to legacy Wringer" do
    Distillator::FetchService.expects(:fetch_result).returns(result(path: "legacy"))
    assert_raises(ResourceLists::MeridianRenderedPage::Invalid) { ResourceLists::MeridianRenderedPage.call(url: URL) }
  end

  test "renderer unavailable is reported without static fallback" do
    Distillator::FetchService.expects(:fetch_result).returns(result(status: :abort, http: nil,
      body: ["abort_update"], success: false))
    error = assert_raises(ResourceLists::MeridianRenderedPage::Invalid) { ResourceLists::MeridianRenderedPage.call(url: URL) }
    assert_match(/Rendered fetch failed/, error.message)
  end

  test "disallows rejected rendered responses" do
    Distillator::FetchService.expects(:fetch_result).returns(result(success: false))
    error = assert_raises(ResourceLists::MeridianRenderedPage::Invalid) { ResourceLists::MeridianRenderedPage.call(url: URL) }
    assert_match(/rejected content/, error.message)
  end

  test "disallows cross-page redirects and oversized HTML" do
    Distillator::FetchService.expects(:fetch_result).returns(result(final_url: "https://meridiancentrepointe.com/fr/evenements?page=0"))
    error = assert_raises(ResourceLists::MeridianRenderedPage::Invalid) { ResourceLists::MeridianRenderedPage.call(url: URL) }
    assert_match(/redirected outside/, error.message)

    Distillator::FetchService.expects(:fetch_result).returns(result(body: "x" * (ResourceLists::MeridianRenderedPage::MAX_HTML_BYTES + 1)))
    error = assert_raises(ResourceLists::MeridianRenderedPage::Invalid) { ResourceLists::MeridianRenderedPage.call(url: URL) }
    assert_match(/oversized HTML/, error.message)
  end
end
