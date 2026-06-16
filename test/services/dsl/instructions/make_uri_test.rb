require "test_helper"

class Dsl::Instructions::MakeUriTest < ActiveSupport::TestCase
  def dummy_ctx(seedurl: "default")
    { seedurl: seedurl }
  end

  test "make_uri preserves cardinality (1:1)" do
    input = ["a", "b", "c"]

    result = Dsl::Instructions::MakeUri.call(input, "", context: dummy_ctx)

    assert_equal input.size, result.size
  end

  test "make_uri never returns nil entries" do
    input = ["", nil, "http://example.com"]

    result = Dsl::Instructions::MakeUri.call(input, "", context: dummy_ctx)

    assert result.all?(&:present?)
  end

  test "fallback id is deterministic" do
    url = "http://example.com/no-id"

    r1 = Dsl::Instructions::MakeUri.call([url], "", context: dummy_ctx).first
    r2 = Dsl::Instructions::MakeUri.call([url], "", context: dummy_ctx).first

    assert_equal r1, r2
  end

  test "extracts id from query param" do
    url = "http://site.com/event?id=123"

    result = Dsl::Instructions::MakeUri.call([url], "", context: dummy_ctx).first

    assert_match(/123$/, result)
  end

  test "extracts id from path segment" do
    url = "http://site.com/events/abc123"

    result = Dsl::Instructions::MakeUri.call([url], "", context: dummy_ctx).first

    assert_match(/abc123$/, result)
  end

  test "expand=true uses expanded url" do
    Dsl::Network::UrlExpander.stubs(:call).returns("http://final.com/event/999")

    result = Dsl::Instructions::MakeUri.call(
      ["http://short.url/x"],
      "expand=true",
      context: dummy_ctx
    ).first

    assert_match(/999$/, result)
  end

  test "expand=false does not call expander" do
    Dsl::Network::UrlExpander.expects(:call).never

    Dsl::Instructions::MakeUri.call(["http://site.com/x"], "expand=false", context: dummy_ctx)
  end

  test "normalizes id" do
    url = "http://site.com/Event Name.html"

    result = Dsl::Instructions::MakeUri.call([url], "", context: dummy_ctx).first

    assert_match(/event-name$/, result)
  end

  test "uses prefix from params" do
    result = Dsl::Instructions::MakeUri.call(["http://x.com/a"], "prefix=test", context: dummy_ctx).first

    assert_match(/^footlight:test_/, result)
  end

  test "uses seedurl as default prefix" do
    ctx = { seedurl: "mysite" }

    result = Dsl::Instructions::MakeUri.call(["http://x.com/a"], "", context: ctx).first

    assert_match(/^footlight:mysite_/, result)
  end

  test "ignores unrelated query params" do
    url = "http://site.com/event?utm_source=abc"

    result = Dsl::Instructions::MakeUri.call([url], "", context: dummy_ctx).first

    assert_no_match(/abc$/, result)
  end

  test "multiple query keys priority uses eventId" do
    url = "http://site.com/event?eventId=456"

    result = Dsl::Instructions::MakeUri.call([url], "", context: dummy_ctx).first

    assert_match(/456$/, result)
  end

  test "known short url expansion detection calls expander when expand is auto" do
    Dsl::Network::UrlExpander.expects(:call).with("https://lpdv.co/abc123", context: dummy_ctx).returns("https://final.site/events/789")

    result = Dsl::Instructions::MakeUri.call(["https://lpdv.co/abc123"], "expand=auto", context: dummy_ctx).first

    assert_match(/789$/, result)
  end

  test "does not expand normal urls" do
    Dsl::Network::UrlExpander.expects(:call).never

    Dsl::Instructions::MakeUri.call(["http://site.com/events/123"], "expand=auto", context: dummy_ctx)
  end

  test "normalization stability collapses duplicate separators" do
    url = "http://site.com/Event--Name.html"

    result = Dsl::Instructions::MakeUri.call([url], "", context: dummy_ctx).first

    assert_match(/event-name$/, result)
  end

  test "fallback remains normalized and present for invalid or empty input" do
    result = Dsl::Instructions::MakeUri.call([nil], "", context: dummy_ctx).first

    assert result.present?
    assert_match(/\Afootlight:[a-z0-9-]+_[a-z0-9-]+\z/, result)
  end
end
