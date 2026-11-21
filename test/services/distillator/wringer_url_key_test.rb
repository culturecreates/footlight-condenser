require "test_helper"

class Distillator::WringerUrlKeyTest < ActiveSupport::TestCase
  test "legacy Culture3R input matches the recorded remote Wringer key after one decode" do
    url = "https://billets.culture3r.com/Online/mapSelect.asp?doWork%3A%3AWSmap%3A%3AloadMap=Load&createBO%3A%3AWSmap=1" \
      "&BOparam%3A%3AWSmap%3A%3AloadMap%3A%3Aperformance_ids=4654FB70-AE58-44D8-B264-6E44B1BB9FC6"
    # Exact key supplied by remote Wringer cache #113047.
    expected = "https%3A%2F%2Fbillets.culture3r.com%2FOnline%2FmapSelect.asp%3FdoWork%3A%3AWSmap%3A%3AloadMap%3DLoad%26createBO%3A%3AWSmap%3D1%26BOparam%3A%3AWSmap%3A%3AloadMap%3A%3Aperformance_ids%3D4654FB70-AE58-44D8-B264-6E44B1BB9FC6"
    assert_equal expected, Distillator::WringerUrlKey.legacy(url, include_fragment: true).uri_key
    assert_equal expected, Distillator::WringerUrlKey.legacy(CGI.unescape(url), include_fragment: true).uri_key
    assert_includes Distillator::WringerUrlKey.call(url, include_fragment: true).uri_key, "%253A"
  end

  test "legacy decoding is exactly once and native keys preserve escaped URL identity" do
    url = "https://example.org/event?value=a%2526b%2Bc&label=a+b#section"
    legacy = Distillator::WringerUrlKey.legacy(url, include_fragment: true)
    assert_equal "https://example.org/event?value=a%26b+c&label=a b#section", legacy.normalized_url
    assert_equal CGI.escape(legacy.normalized_url), legacy.uri_key
    assert_equal url, Distillator::WringerUrlKey.call(url, include_fragment: true).normalized_url
    assert_not_equal Distillator::WringerUrlKey.call(url, include_fragment: true).uri_key, legacy.uri_key
  end

  test "http culturecreates root matches legacy make_uri_key" do
    result = Distillator::WringerUrlKey.call("http://culturecreates.com/")

    assert_equal "http%3A%2F%2Fculturecreates.com%2F", result.uri_key
    assert_equal "http://culturecreates.com/", result.normalized_url
  end

  test "uri key with no scheme injects http like legacy make_uri_key" do
    result = Distillator::WringerUrlKey.call("culturecreates.com/")

    assert_equal "http%3A%2F%2Fculturecreates.com%2F", result.uri_key
    assert_equal "http://culturecreates.com/", result.normalized_url
  end

  test "uri key preserves query like legacy make_uri_key" do
    result = Distillator::WringerUrlKey.call("https://billetterie.lachapelle.org/dates.aspx?codeEvent=TEM2017-2018")

    assert_equal "https%3A%2F%2Fbilletterie.lachapelle.org%2Fdates.aspx%3FcodeEvent%3DTEM2017-2018", result.uri_key
    assert_equal "https://billetterie.lachapelle.org/dates.aspx?codeEvent=TEM2017-2018", result.normalized_url
  end

  test "uri key excludes fragment by default like legacy make_uri_key" do
    result = Distillator::WringerUrlKey.call("https://culturecreates.com/people#gregory")

    assert_equal "https%3A%2F%2Fculturecreates.com%2Fpeople", result.uri_key
    assert_equal "https://culturecreates.com/people", result.normalized_url
  end

  test "uri key includes fragment when requested like legacy make_uri_key" do
    result = Distillator::WringerUrlKey.call("https://culturecreates.com/people#gregory", include_fragment: true)

    assert_equal "https%3A%2F%2Fculturecreates.com%2Fpeople%23gregory", result.uri_key
    assert_equal "https://culturecreates.com/people#gregory", result.normalized_url
  end

  test "uri key includes fragment when include_fragment is string true" do
    result = Distillator::WringerUrlKey.call("https://culturecreates.com/people#gregory", include_fragment: "true")

    assert_equal "https%3A%2F%2Fculturecreates.com%2Fpeople%23gregory", result.uri_key
  end

  test "uri key with no scheme preserves trailing path slash like legacy make_uri_key" do
    result = Distillator::WringerUrlKey.call("culturecreates.com/people/")

    assert_equal "http%3A%2F%2Fculturecreates.com%2Fpeople%2F", result.uri_key
    assert_equal "http://culturecreates.com/people/", result.normalized_url
  end

  test "uri key preserves legacy case-sensitive scheme quirk for uppercase scheme input" do
    result = Distillator::WringerUrlKey.call("HTTPS://Example.org/People/")

    # This intentionally matches Wringer's current case-sensitive `http` prefix check.
    assert_equal "http%3A%2F%2FHTTPS%2F%2FExample.org%2FPeople%2F", result.uri_key
    assert_equal "http://HTTPS//Example.org/People/", result.normalized_url
  end

  test "blank URL raises invalid uri error instead of generating a cache key" do
    assert_raises(Addressable::URI::InvalidURIError) do
      Distillator::WringerUrlKey.call("")
    end
  end

  test "uri key exact outputs match rollout contract cases" do
    assert_equal "http%3A%2F%2Fculturecreates.com%2F", Distillator::WringerUrlKey.call("http://culturecreates.com/").uri_key
    assert_equal "https%3A%2F%2Fculturecreates.com%2Fpeople", Distillator::WringerUrlKey.call("https://culturecreates.com/people#gregory").uri_key
    assert_equal "https%3A%2F%2Fculturecreates.com%2Fpeople%23gregory", Distillator::WringerUrlKey.call("https://culturecreates.com/people#gregory", include_fragment: true).uri_key
    assert_equal "http%3A%2F%2Fculturecreates.com%2Fpeople%2F", Distillator::WringerUrlKey.call("culturecreates.com/people/").uri_key
  end

  test "invalid URI raises so controller can return no_content" do
    assert_raises(URI::InvalidURIError) do
      Distillator::WringerUrlKey.call("http://[invalid")
    end
  end

  test "already escaped URL stays on the legacy error path deterministically" do
    result = Distillator::WringerUrlKey.call("https%3A%2F%2Fculturecreates.com%2Fpeople%2F")

    assert_equal "Error%3A+not+a+URI", result.uri_key
    assert_equal "Error: not a URI", result.normalized_url
  end

  test "uri key excludes fragment when include_fragment is false even if upstream helper preserved it" do
    result = Distillator::WringerUrlKey.call("https://culturecreates.com/people#gregory", include_fragment: false)

    assert_equal "https://culturecreates.com/people", result.normalized_url
  end

  test "uri key excludes fragment when include_fragment is string false" do
    result = Distillator::WringerUrlKey.call("https://culturecreates.com/people#gregory", include_fragment: "false")

    assert_equal "https://culturecreates.com/people", result.normalized_url
  end
end
