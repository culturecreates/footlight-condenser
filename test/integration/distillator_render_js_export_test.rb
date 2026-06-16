require "test_helper"
require Rails.root.join("test/support/distillator_integration_event_factory")

class DistillatorRenderJsExportTest < ActionDispatch::IntegrationTest
  setup do
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    Distillator::FetchCache.delete_all
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
  end

  test "render_js source uses legacy fallback metadata and exports refreshed value" do
    website, event_page, title_statement = build_publishable_event(
      seedurl: "distillator-render-js-export",
      rdf_uri: "footlight:render-js-event",
      algorithm_value: "xpath=//h1/text()",
      render_js: true,
      initial_title: "Old Render JS Title"
    )

    Distillator::LegacyWringerFetch.expects(:fetch).once.returns(
      status: :ok,
      body: "<html><body><h1>Rendered Export Title</h1></body></html>",
      raw_body: "<html><body><h1>Rendered Export Title</h1></body></html>",
      headers: { content_type: "text/html" },
      final_url: event_page.url,
      redirect_chain: [event_page.url],
      wringer: { signals: { network_status: "ok" }, hints: [] },
      http_code: 200
    )

    patch refresh_statement_path(title_statement)

    assert_redirected_to statement_url(title_statement)
    assert_equal "Rendered Export Title", title_statement.reload.cache
    cache = Distillator::FetchCache.find_by(normalized_url: event_page.url)
    assert_equal "legacy", cache.signals["fetch_path"]
    assert_includes ExportArtsdataService.call(seedurl: website.seedurl), "Rendered Export Title"
  end

  private

  include DistillatorIntegrationEventFactory
end
