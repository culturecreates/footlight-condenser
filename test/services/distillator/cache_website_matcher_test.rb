require "test_helper"

class Distillator::CacheWebsiteMatcherTest < ActiveSupport::TestCase
  test "matches exact webpage url" do
    website = build_website_with_page("https://example.org/event")
    cache = Distillator::FetchCache.new(uri_key: CGI.escape("https://example.org/event"), normalized_url: "https://example.org/event")

    result = Distillator::CacheWebsiteMatcher.call(cache: cache, websites: [website])

    assert_equal website, result.website
    assert_equal "webpage_url", result.matched_by
  end

  test "matches trailing slash difference" do
    website = build_website_with_page("https://example.org/event/")
    cache = Distillator::FetchCache.new(uri_key: CGI.escape("https://example.org/event"), normalized_url: "https://example.org/event")

    result = Distillator::CacheWebsiteMatcher.call(cache: cache, websites: [website])

    assert_equal website, result.website
    assert_equal "canonical_without_fragment", result.matched_by
  end

  test "matches final url redirect with warning" do
    website = build_website_with_page("https://example.org/event")
    cache = Distillator::FetchCache.new(
      uri_key: CGI.escape("https://example.org/original"),
      normalized_url: "https://example.org/original",
      final_url: "https://example.org/event"
    )

    result = Distillator::CacheWebsiteMatcher.call(cache: cache, websites: [website])

    assert_equal website, result.website
    assert_equal "final_url", result.matched_by
    assert_equal "final_url_redirect_match", result.warning
  end

  test "does not silently guess ambiguous matches" do
    one = build_website_with_page("https://example.org/shared")
    two = build_website_with_page("https://example.org/shared")
    cache = Distillator::FetchCache.new(uri_key: CGI.escape("https://example.org/shared"), normalized_url: "https://example.org/shared")

    result = Distillator::CacheWebsiteMatcher.call(cache: cache, websites: [one, two])

    assert_nil result.website
    assert_equal "ambiguous_cache_match", result.warning
  end

  private

  def build_website_with_page(url)
    website = Website.create!(
      name: "Matcher #{SecureRandom.hex(4)}",
      seedurl: "matcher-#{SecureRandom.hex(4)}",
      graph_name: "https://example.org/#{SecureRandom.hex(4)}",
      default_language: "en",
      distillator_mode: "shadow"
    )
    website.webpages.create!(url: url, language: "en", rdf_uri: "rdf:#{SecureRandom.hex(4)}", rdfs_class: rdfs_classes(:one))
    website
  end
end
