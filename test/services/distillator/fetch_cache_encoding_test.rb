require "test_helper"

class Distillator::FetchCacheEncodingTest < ActiveSupport::TestCase
  TITLE = "Chic Shack - décembre 2026 - Le Petit Théâtre du Vieux Noranda".freeze
  HTML = "<html><head><title>#{TITLE}</title></head><body>Événement</body></html>".freeze
  URL = "https://example.org/encoding-regression".freeze

  test "fresh binary UTF-8 HTML is decoded before title extraction and cache storage" do
    raw = HTML.b
    result = fetch_html(raw, headers: { "Content-Type" => 'text/html; charset="UTF-8"' })

    assert_equal Encoding::UTF_8, result.html.encoding
    assert_equal Encoding::UTF_8, result.body.encoding
    assert_equal Encoding::UTF_8, result.cache.html.encoding
    assert_equal HTML, result.html
    assert_equal HTML.bytes, result.html.bytes
    assert_equal TITLE, result.name
    assert_equal Encoding::ASCII_8BIT, raw.encoding
    assert_equal HTML.bytes, raw.bytes
  end

  test "fresh and PostgreSQL-reloaded comparisons have identical title verdicts and summaries" do
    result = fetch_html(HTML.b)
    fresh = compare(result)
    reloaded = compare(Struct.new(:cache).new(Distillator::FetchCache.find(result.cache.id)))

    assert fresh.dig(:diffs, :html_sha256, :same)
    assert fresh.dig(:diffs, :title, :same)
    assert_equal TITLE, fresh.dig(:diffs, :title, :condenser)
    assert_not_includes fresh.dig(:summary, :blocking_regressions), :title
    assert_equal reloaded[:summary], fresh[:summary]
    assert_equal reloaded.dig(:diffs, :title), fresh.dig(:diffs, :title)
  end

  test "declared ISO-8859-1 HTML is converted to UTF-8 without replacement characters" do
    raw = HTML.encode(Encoding::ISO_8859_1).b
    original_bytes = raw.bytes
    result = fetch_html(raw, headers: { "content-type" => "text/html; charset=ISO-8859-1" })

    assert_equal Encoding::UTF_8, result.html.encoding
    assert_equal HTML, result.html
    assert_equal TITLE, result.name
    assert_equal HTML, Distillator::FetchCache.find(result.cache.id).html
    assert_equal original_bytes, raw.bytes
    assert_equal Encoding::ASCII_8BIT, raw.encoding
  end

  test "UTF-8 HTML without a declared charset is normalized" do
    assert_equal HTML, fetch_html(HTML.b, headers: { content_type: "text/html" }).html
  end

  test "missing content type produces the same fresh and reloaded comparison" do
    result = fetch_html(HTML.b, headers: {})
    assert_equal Encoding::UTF_8, result.html.encoding
    assert_equal TITLE, result.name
    assert_equal compare(result)[:summary], compare(Struct.new(:cache).new(result.cache.reload))[:summary]
    assert compare(result).dig(:diffs, :title, :same)
  end

  test "meta-only Latin1 HTML survives PostgreSQL and does not get decoded twice" do
    html = HTML.sub("<head>", '<head><meta charset="ISO-8859-1">')
    result = fetch_html(html.encode("ISO-8859-1").b, headers: {})
    assert_equal html, result.html
    assert_equal html, result.cache.reload.html
    assert_equal TITLE, result.name
  end

  test "already decoded fetch with a Latin1 header preserves the title" do
    result = fetch_html(HTML, headers: { content_type: "text/html; charset=ISO-8859-1" })
    assert_equal HTML, result.html
    assert_equal TITLE, result.name
  end

  test "invalid UTF-8 and unsupported charsets preserve the original bytes and encoding" do
    invalid = "<html><title>invalid \xC3</title></html>".b
    unsupported = HTML.b
    [[invalid, "text/html; charset=UTF-8"], [unsupported, "text/html; charset=not-a-real-charset"]].each do |body, type|
      decoded = decode(body, content_type: type)
      assert_same body, decoded
      assert_equal body.bytes, decoded.bytes
      assert_equal Encoding::ASCII_8BIT, decoded.encoding
    end
  end

  test "non-HTML responses and non-string bodies are left unchanged" do
    body = "\xFF\x00\xC3".b
    assert_same body, decode(body, content_type: "application/octet-stream")
    control = ["abort_update", { error: "fetch failed" }]
    assert_same control, decode(control, content_type: "text/html; charset=UTF-8")
    assert_nil decode(nil, content_type: "text/html")
  end

  private

  def decode(body, headers)
    Distillator::FetchCacheStore.new(uri: URL).send(:decode_html_body, body, headers)
  end

  def fetch_html(body, headers: { content_type: "text/html; charset=UTF-8" })
    Distillator::FetchService.expects(:fetch_result).returns(
      status: :ok, body: body, raw_body: body, headers: headers, http_code: 200,
      final_url: URL, redirect_chain: [URL], fetch_path: "native", duration_ms: 1,
      wringer: { signals: { network_status: "ok", content_type: "html" }, hints: [] }
    )
    Distillator::FetchCacheStore.fetch(uri: URL, mode: :internal, force_scrape: true)
  end

  def compare(result)
    Distillator::CacheCompare.call(uri: URL, condenser_result: result,
      legacy_lookup: ->(_) { { html: HTML, http_code: 200, final_url: URL,
        signals: { network_status: "ok", content_type: "html", transport_success: true, content_success: true } } })
  end
end
