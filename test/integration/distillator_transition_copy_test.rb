require "cgi"
require "test_helper"

class DistillatorTransitionCopyTest < ActiveSupport::TestCase
  LIVE_TRANSITION_FILES = [
    Rails.root.join("app/views/shared/_transition_context.html.erb"),
    Rails.root.join("app/views/websites/show.html.erb"),
    Rails.root.join("app/views/websites/index.html.erb"),
    Rails.root.join("app/views/distillator/shadow_reports/index.html.erb"),
    Rails.root.join("app/views/distillator/shadow_reports/show.html.erb")
  ].freeze

  FORBIDDEN_PHRASES = [
    "distillator rollout",
    "new cache"
  ].freeze

  test "live transition workflow files do not reintroduce retired rollout wording" do
    contents = LIVE_TRANSITION_FILES.to_h { |path| [path, File.read(path)] }

    FORBIDDEN_PHRASES.each do |phrase|
      contents.each do |path, content|
        refute_includes content, phrase, "#{path} unexpectedly included #{phrase.inspect}"
      end
    end
  end
end

class DistillatorTransitionContextIntegrationTest < ActionDispatch::IntegrationTest
  FORBIDDEN_VISIBLE_TERMS = [
    "internal rollout",
    "replay diagnostic",
    "phase i",
    "phase ii",
    "phase iii",
    "preview only",
    "new cache",
    "distillator rollout"
  ].freeze

  test "webpages index renders compact transition context from website cookie" do
    website = Website.create!(
      name: "Context website",
      seedurl: "context-website",
      graph_name: "https://example.org/context-website",
      default_language: "en",
      distillator_mode: "shadow"
    )

    get website_url(website)
    assert_response :success

    get webpages_url

    assert_response :success
    assert_includes @response.body, "Transition context"
    assert_includes @response.body, website.name
    assert_includes @response.body, "Current mode:</strong> Shadow"
    assert_includes @response.body, "Production backend:</strong> Wringer"
    assert_includes @response.body, "Transition report"
  end

  test "webpages index stays compact when no website context exists" do
    get webpages_url

    assert_response :success
    assert_not_includes @response.body, "Transition context"
  end

  test "live operator pages avoid retired rollout terms" do
    website = Website.create!(
      name: "Operator website",
      seedurl: "operator-website",
      graph_name: "https://example.org/operator-website",
      default_language: "en",
      distillator_mode: "shadow"
    )
    webpage = website.webpages.create!(
      url: "https://example.org/operator-website/event",
      language: "en",
      rdf_uri: "rdf:operator-website:event",
      rdfs_class: rdfs_classes(:one)
    )
    cache = Distillator::FetchCache.create!(
      uri_key: CGI.escape(webpage.url),
      normalized_url: webpage.url,
      name: website.name,
      html: "<html>cached</html>",
      body: "<html>cached</html>",
      http_response_code: 200,
      scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago,
      headers: {},
      signals: { "transport_success" => true, "content_success" => true, "export_diff_checked" => true },
      final_url: webpage.url,
      redirect_chain: [],
      health_status: "healthy",
      health_severity: "ok"
    )

    Distillator::CacheCompare.stubs(:call).returns(
      {
        uri: webpage.url,
        uri_key: CGI.escape(webpage.url),
        legacy_cache: { html: "<html>legacy</html>" },
        legacy_source: "wringer_lookup",
        legacy_lookup_error: nil,
        condenser_cache: { html: "<html>condenser</html>" },
        condenser_source: "local_fetch_cache",
        diffs: {},
        summary: {},
        missing: { legacy: false, condenser: false }
      }
    )

    [
      websites_url,
      website_url(website),
      distillator_shadow_report_path,
      distillator_shadow_report_site_path(website),
      distillator_cache_index_path,
      distillator_cache_path(cache),
      condenser_cache_compare_path(uri: webpage.url),
      preview_distillator_cache_index_path(uri: webpage.url)
    ].each do |path|
      get path
      assert_response :success

      visible = ActionView::Base.full_sanitizer.sanitize(@response.body).downcase
      FORBIDDEN_VISIBLE_TERMS.each do |term|
        refute_includes visible, term, "#{path} unexpectedly included #{term.inspect}"
      end
    end
  end
end
