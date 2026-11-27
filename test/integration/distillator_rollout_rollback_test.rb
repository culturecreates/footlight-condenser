require "test_helper"

class DistillatorRolloutRollbackTest < ActionDispatch::IntegrationTest
  test "active to legacy rollback keeps read only inspection and backend semantics safe" do
    ApplicationController.helpers.stubs(:get_wringer_url_per_environment).returns("http://wringer.example")
    website = Website.create!(
      name: "Rollback site",
      seedurl: "rollback-site",
      graph_name: "https://example.org/rollback-site",
      default_language: "en",
      distillator_mode: "active"
    )

    payload = Distillator::CacheLinkResolver.call(url: "http://example.org/page", website: website)
    assert_equal :condenser, payload[:active_backend]
    assert_equal payload[:distillator_cache_url], payload[:active_cache_url]

    patch website_url(website), params: { website: { distillator_mode: "legacy" } }

    assert_redirected_to website_url(website)
    website.reload
    assert_equal "legacy", website.distillator_mode

    payload = Distillator::CacheLinkResolver.call(url: "http://example.org/page", website: website)
    assert_equal :wringer, payload[:active_backend]
    assert_equal payload[:legacy_cache_url], payload[:active_cache_url]
    assert_equal "Open Condenser cache", payload[:secondary_links].first[:label]

    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never

    get website_url(website)
    assert_response :success
  end

  test "active transition detail page shows rollback guidance and remains read only" do
    ApplicationController.helpers.stubs(:get_wringer_url_per_environment).returns("http://wringer.example")
    website = Website.create!(
      name: "Rollback detail site",
      seedurl: "rollback-detail-site",
      graph_name: "https://example.org/rollback-detail-site",
      default_language: "en",
      distillator_mode: "active"
    )

    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never

    get distillator_shadow_report_site_path(website)

    assert_response :success
    assert_includes @response.body, "Rollback path"
    assert_includes @response.body, "Set rollout mode to Legacy in website options."
    assert_includes @response.body, "Wringer becomes production backend."
    assert_includes @response.body, "Condenser cache remains available for inspection."
  end
end
