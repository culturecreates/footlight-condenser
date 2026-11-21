require "test_helper"

class DistillatorRefreshThenExportTest < ActionDispatch::IntegrationTest
  setup do
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"
    Distillator::FetchCache.delete_all
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
  end

  test "native refresh updates statement cache and export uses refreshed value" do
    website = Website.create!(
      name: "Refresh Export Fixture",
      seedurl: "distillator-refresh-export",
      graph_name: "https://fixtures.example/refresh-export",
      default_language: "en",
      distillator_mode: "active"
    )
    event_page = Webpage.create!(
      website: website,
      rdfs_class: rdfs_classes(:one),
      url: "https://fixtures.example/refresh-export/event",
      rdf_uri: "footlight:refresh-export-event",
      language: "en",
      archive_date: Time.zone.parse("2026-06-01T00:00:00Z")
    )
    place_page = Webpage.create!(
      website: website,
      rdfs_class: rdfs_classes(:place),
      url: "https://fixtures.example/refresh-export/place",
      rdf_uri: "footlight:refresh-export-place",
      language: "en",
      archive_date: Time.zone.parse("2026-06-01T00:00:00Z")
    )

    place_source = Source.create!(
      algorithm_value: "manual=Main Hall",
      selected: true,
      selected_by: "test",
      render_js: false,
      property: properties(:two),
      website: website
    )
    Statement.create!(
      cache: "Main Hall",
      status: "ok",
      status_origin: "test",
      cache_refreshed: 1.day.ago,
      cache_changed: 1.day.ago,
      source: place_source,
      webpage: place_page,
      selected_individual: true
    )

    title_source = Source.create!(
      algorithm_value: "xpath=//h1/text()",
      selected: true,
      selected_by: "test",
      language: "en",
      render_js: false,
      property: properties(:four),
      website: website
    )
    dates_source = Source.create!(
      algorithm_value: "manual=dates",
      selected: true,
      selected_by: "test",
      render_js: false,
      property: properties(:ten),
      website: website
    )
    location_source = Source.create!(
      algorithm_value: "manual=location",
      selected: true,
      selected_by: "test",
      render_js: false,
      property: properties(:location),
      website: website
    )

    title_statement = Statement.create!(
      cache: "Old Export Title",
      status: "initial",
      status_origin: "test",
      cache_refreshed: 1.day.ago,
      cache_changed: 1.day.ago,
      source: title_source,
      webpage: event_page,
      selected_individual: true
    )
    previous_refreshed = title_statement.cache_refreshed
    previous_changed = title_statement.cache_changed
    Statement.create!(
      cache: "[\"2026-05-10T19:30:00-04:00\"]",
      status: "ok",
      status_origin: "test",
      cache_refreshed: 1.day.ago,
      cache_changed: 1.day.ago,
      source: dates_source,
      webpage: event_page,
      selected_individual: true
    )
    Statement.create!(
      cache: "[\"Main Hall\",\"Place\",[\"Main Hall\",\"footlight:refresh-export-place\"]]",
      status: "ok",
      status_origin: "test",
      cache_refreshed: 1.day.ago,
      cache_changed: 1.day.ago,
      source: location_source,
      webpage: event_page,
      selected_individual: true
    )

    html = "<html><body><h1>Refreshed Export Title</h1></body></html>"
    Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::FetchGuard.stubs(:check_response).returns(Distillator::FetchGuard::Result.new(allowed: true))
    Distillator::NativeFetch.expects(:call).once.returns(
      status: :ok,
      body: html,
      raw_body: html,
      headers: { content_type: "text/html" },
      final_url: event_page.url,
      redirect_chain: [event_page.url],
      wringer: { signals: {}, hints: [] },
      http_code: 200
    )

    patch refresh_rdf_uri_statements_path(format: :json), params: {
      rdf_uri: event_page.rdf_uri,
      force_scrape_every_hrs: "0"
    }

    assert_response :success
    assert_equal "Refreshed Export Title", title_statement.reload.cache
    assert_operator title_statement.cache_refreshed, :>, previous_refreshed
    assert_operator title_statement.cache_changed, :>, previous_changed
    export = ExportArtsdataService.call(seedurl: website.seedurl)

    assert_includes export, "Refreshed Export Title"
    refute_includes export, "Old Export Title"
    assert Distillator::FetchCache.find_by(normalized_url: event_page.url).present?
  end
end
