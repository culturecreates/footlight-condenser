require "test_helper"

class Dsl::Support::UrlResolverTest < ActiveSupport::TestCase
  test "extract returns normalized url for string input" do
    value = " https://example.com/events/1#tickets "

    assert_equal "https://example.com/events/1#tickets", Dsl::Support::UrlResolver.extract(value)
  end

  test "extract returns first valid url from mixed array input" do
    value = [nil, "not-a-url", "https://first.example.com/path#fragment", "https://second.example.com"]

    assert_equal "https://first.example.com/path#fragment", Dsl::Support::UrlResolver.extract(value)
  end

  test "extract returns nil for hash input" do
    value = { "url" => "https://example.com" }

    assert_nil Dsl::Support::UrlResolver.extract(value)
  end

  test "extract returns first valid url from json string input" do
    value = "https://json.example.com/tickets#purchase".to_json

    assert_equal "https://json.example.com/tickets#purchase", Dsl::Support::UrlResolver.extract(value)
  end

  test "extract returns nil for invalid url input" do
    value = "ftp://example.com/file"

    assert_nil Dsl::Support::UrlResolver.extract(value)
  end

  test "extract returns nil for nil input" do
    assert_nil Dsl::Support::UrlResolver.extract(nil)
  end
end
