require "test_helper"

class Distillator::HtmlContentTest < ActiveSupport::TestCase
  HTML = '<html><head><title>Théâtre décembre</title></head></html>'.freeze

  test "missing MIME recognizes HTML after comments without changing bytes" do
    raw = "<!-- generated -->\n#{HTML}".b
    decoded = Distillator::HtmlContent.decode(raw)
    assert_equal Encoding::UTF_8, decoded.encoding
    assert_equal raw.bytes, decoded.bytes
    assert_equal Encoding::BINARY, raw.encoding
    assert_equal "Théâtre décembre", Distillator::HtmlContent.title(decoded)
  end

  test "already decoded text is idempotent even when an old header declares Latin1" do
    headers = { "Content-Type" => "text/html; charset=ISO-8859-1" }
    decoded = Distillator::HtmlContent.decode(HTML, headers: headers)
    assert_equal HTML, decoded
    assert_equal decoded, Distillator::HtmlContent.decode(decoded, headers: headers)
    assert_equal HTML, Distillator::HtmlContent.decode(HTML.encode("ISO-8859-1"), headers: headers)
  end

  test "meta charset and http equiv decode raw Latin1 while ignoring comments" do
    declarations = ['<meta charset="ISO-8859-1">',
      "<meta content='text/html; charset=ISO-8859-1' http-equiv='Content-Type'>"]
    declarations.each do |declaration|
      html = HTML.sub("<head>", "<head><!-- <meta charset='UTF-8'> -->#{declaration}")
      assert_equal html, Distillator::HtmlContent.decode(html.encode("ISO-8859-1").b)
    end
    commented = "<html><!-- <meta charset='ISO-8859-1'> Théâtre"
    assert_equal commented, Distillator::HtmlContent.decode(commented.b)
  end

  test "BOM has priority over conflicting declarations and is removed" do
    Distillator::HtmlContent::BOMS.each do |bom, encoding|
      raw = bom + HTML.encode(encoding).b
      result = Distillator::HtmlContent.decode(raw, headers: { content_type: "text/html; charset=ISO-8859-1" })
      assert_equal HTML, result, encoding
      assert_equal Encoding::UTF_8, result.encoding
      assert_equal bom + HTML.encode(encoding).b, raw
    end
  end

  test "HTTP charset takes precedence over a conflicting meta declaration for raw bytes" do
    html = HTML.sub("<head>", "<head><meta charset='UTF-8'>")
    assert_equal html, Distillator::HtmlContent.decode(html.encode("ISO-8859-1").b,
      headers: { content_type: "text/html; charset=ISO-8859-1" })
  end

  test "invalid or unknown raw encodings remain byte exact and non HTML is untouched" do
    [["<html>\xC3".b, "text/html; charset=UTF-8"],
      [HTML.b, "text/html; charset=unknown-charset"],
      [HTML.b, "application/json"], ["{\"name\":\"été\"}".b, ""],
      ["\xEF\xBB\xBF{\"name\":\"été\"}".b, ""]].each do |raw, type|
      assert_same raw, Distillator::HtmlContent.decode(raw, headers: { content_type: type })
    end
  end

  test "title uses HTML parsing entities whitespace and canonical Unicode normalization" do
    assert_equal "Théâtre & décembre", Distillator::HtmlContent.title(
      "<HTML><HEAD><TITLE data-test='title'>  The\u0301a\u0302tre &#38;\n décembre </TITLE></HEAD></HTML>".b)
    assert_equal "Théâtre & décembre", Distillator::HtmlContent.title(
      "<title>Théâtre &amp; décembre</title>")
  end
end
