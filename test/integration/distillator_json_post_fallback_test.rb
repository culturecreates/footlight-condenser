require "test_helper"
require Rails.root.join("test/support/distillator_integration_event_factory")

class DistillatorJsonPostFallbackTest < ActionDispatch::IntegrationTest
  include DistillatorIntegrationEventFactory

  setup do
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    Distillator::FetchCache.delete_all
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::FetchGuard.stubs(:check_response).returns(Distillator::FetchGuard::Result.new(allowed: true))
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
  end

  test "active website post_url refresh uses native json post and caches post metadata" do
    website, event_page, title_statement = build_publishable_event(
      seedurl: "distillator-json-post-fallback",
      rdf_uri: "footlight:json-post-fallback-event",
      algorithm_value: "post_url=$url;json=$json.dig('name')",
      render_js: false,
      initial_title: "Old Native JSON Post Title",
      json_post: true
    )
    website.update!(distillator_mode: "active")

    Distillator::NativeFetch.expects(:call).once.with do |kwargs|
      assert_equal event_page.url, kwargs[:url]
      assert_equal false, kwargs[:render_js]
      assert_equal true, kwargs[:scrape_options][:json_post]
      true
    end.returns(
      status: :ok,
      body: '{"name":"Native JSON Post Title"}',
      raw_body: '{"name":"Native JSON Post Title"}',
      headers: { content_type: "application/json" },
      final_url: event_page.url,
      redirect_chain: [event_page.url],
      wringer: {
        signals: { network_status: "ok", content_type: "json", request_method: "POST" },
        hints: ["json_detected"]
      },
      http_code: 200
    )

    patch refresh_statement_path(title_statement)

    assert_redirected_to statement_url(title_statement)
    assert_equal "Native JSON Post Title", title_statement.reload.cache
    cache = Distillator::FetchCache.find_by!(normalized_url: event_page.url)
    assert_equal "native", cache.signals["fetch_path"]
    assert_equal "POST", cache.signals["request_method"]
    assert_equal "json", cache.signals["content_type"]
    assert_includes cache.hints, "json_detected"
    assert_includes ExportArtsdataService.call(seedurl: website.seedurl), "Native JSON Post Title"
  end
end
