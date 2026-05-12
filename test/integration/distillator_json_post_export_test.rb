require "test_helper"
require Rails.root.join("test/support/distillator_integration_event_factory")

class DistillatorJsonPostExportTest < ActionDispatch::IntegrationTest
  setup do
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    Distillator::FetchCache.delete_all
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
  end

  test "json_post source uses legacy fallback metadata and exports parsed json value" do
    website, event_page, title_statement = build_publishable_event(
      seedurl: "distillator-json-post-export",
      rdf_uri: "footlight:json-post-event",
      algorithm_value: "post_url=$url;json=$json.dig('name')",
      render_js: false,
      initial_title: "Old JSON Post Title",
      json_post: true
    )

    Distillator::LegacyWringerFetch.expects(:fetch).once.returns(
      status: :ok,
      body: '{"name":"JSON Post Export Title"}',
      raw_body: '{"name":"JSON Post Export Title"}',
      headers: { content_type: "application/json" },
      final_url: event_page.url,
      redirect_chain: [event_page.url],
      wringer: { signals: { network_status: "ok", content_type: "json" }, hints: ["json_detected"] },
      http_code: 200
    )

    patch refresh_statement_path(title_statement)

    assert_redirected_to statement_url(title_statement)
    assert_equal "JSON Post Export Title", title_statement.reload.cache
    cache = Distillator::FetchCache.find_by(normalized_url: event_page.url)
    assert_equal "legacy", cache.signals["fetch_path"]
    assert_equal "json", cache.signals["content_type"]
    assert_includes cache.hints, "json_detected"
    assert_includes ExportArtsdataService.call(seedurl: website.seedurl), "JSON Post Export Title"
  end

  private

  include DistillatorIntegrationEventFactory
end
