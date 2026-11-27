require "test_helper"

class DslContentParserTest < ActiveSupport::TestCase
  # === Set up a parser from raw HTML or text ===

  def parser_for_html(html)
    Dsl::Parsing::ContentParser.new(html: html)
  end

  def test_xpath_extracts_text
    html = "<html><body><p>Hello World</p><p>Foo</p></body></html>"
    parser = parser_for_html(html)

    assert_equal ["Hello World", "Foo"], parser.parse_step("xpath", "//p/text()")
  end

  def test_css_extracts_text
    html = "<html><body><span class='x'>Bar</span><span class='x'>Baz</span></body></html>"
    parser = parser_for_html(html)

    assert_equal %w[Bar Baz], parser.parse_step("css", ".x")
  end

  def test_json_prefix_parses_json_value
    json_hash = { "name" => "value", "nested" => { "k" => "v" } }
    json_str = json_hash.to_json

    parser = Dsl::Parsing::ContentParser.new(html: json_str)
    result = parser.parse_step("json", "$json['nested']['k']")

    assert_equal "v", result
  end

  def test_ruby_prefix_can_transform_array
    html = "<html><body><p>A</p><p>B</p></body></html>"
    parser = parser_for_html(html)

    arr = %w[a b]
    result = parser.parse_step("ruby", "$array.map(&:upcase)", arr)

    assert_equal %w[A B], result
  end

  def test_time_zone_prefix_returns_array
    parser = parser_for_html("anything")
    result = parser.parse_step("time_zone", "UTC")

    assert_equal ["time_zone: UTC"], result
  end

  def test_if_xpath_returns_empty_when_no_match
    html = "<html><body></body></html>"
    parser = parser_for_html(html)

    assert_empty parser.parse_step("if_xpath", "//missing")
  end

  def test_unless_xpath_returns_original_array_when_no_match
    html = "<html><body></body></html>"
    parser = parser_for_html(html)

    arr = ["foo"]
    assert_equal ["foo"], parser.parse_step("unless_xpath", "//missing", arr)
  end

  def test_unless_xpath_returns_empty_when_match_present
    html = "<html><body><p>Only</p></body></html>"
    parser = parser_for_html(html)

    assert_empty parser.parse_step("unless_xpath", "//p")
  end

  def test_xpath_sanitize_removes_unwanted_tags
    html = <<~HTML
      <html><body><p>Keep</p><script>Bad</script><style>Bad2</style></body></html>
    HTML
    parser = parser_for_html(html)

    result = parser.parse_step("xpath_sanitize", "//body/*")
    assert_equal ["Keep"], result
  end

  def test_parse_json_raises_on_invalid_json
    invalid_json = "not a json string"
    parser = Dsl::Parsing::ContentParser.new(html: invalid_json)

    assert_raises(JSON::ParserError) do
      parser.parse_step("json", "$json['foo']")
    end
  end
end