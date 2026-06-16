require "test_helper"

class DistillatorManualLinkExportTest < ActionDispatch::IntegrationTest
  test "manual linked data is export-visible and manual ok statements are not overwritten by refresh" do
    website = Website.create!(
      name: "Manual Link Fixture",
      seedurl: "distillator-manual-link-export",
      graph_name: "https://fixtures.example/manual-link-export",
      default_language: "en"
    )
    event_page = Webpage.create!(
      website: website,
      rdfs_class: rdfs_classes(:one),
      url: "https://fixtures.example/manual-link-export/event",
      rdf_uri: "footlight:manual-link-event",
      language: "en",
      archive_date: Time.zone.parse("2026-06-01T00:00:00Z")
    )
    org_page = Webpage.create!(
      website: website,
      rdfs_class: rdfs_classes(:organization),
      url: "https://fixtures.example/manual-link-export/org",
      rdf_uri: "footlight:manual-link-org",
      language: "en",
      archive_date: Time.zone.parse("2026-06-01T00:00:00Z")
    )

    create_statement_with_source!(website:, webpage: org_page, property: properties(:organizationName), algorithm_value: "manual=Venue Org", cache: "Venue Org", status: "ok")
    create_statement_with_source!(website:, webpage: event_page, property: properties(:four), algorithm_value: "manual=Manual Link Event", cache: "Manual Link Event", status: "ok", language: "en")
    create_statement_with_source!(website:, webpage: event_page, property: properties(:ten), algorithm_value: "manual=2026-05-10", cache: "[\"2026-05-10T19:30:00-04:00\"]", status: "ok")
    create_statement_with_source!(website:, webpage: event_page, property: properties(:location), algorithm_value: "manual=Main Hall", cache: "[\"Main Hall\",\"Place\",[\"Main Hall\",\"footlight:manual-link-place\"]]", status: "ok")

    performer_statement = create_statement_with_source!(
      website: website,
      webpage: event_page,
      property: properties(:nine),
      algorithm_value: "manual=Venue Org",
      cache: "[\"Manually added\",\"Organization\",[\"Venue Org\",\"footlight:manual-link-org\"]]",
      status: "ok",
      manual: true
    )

    export = ExportArtsdataService.call(seedurl: website.seedurl)
    assert_includes export, "manual-link-org"

    result = ApplicationController.helpers.refresh_statement_helper(performer_statement)
    assert_includes result[:errors].join(" "), "No update unless status is 'initial', 'problem', or 'missing'."
    assert_equal "[\"Manually added\",\"Organization\",[\"Venue Org\",\"footlight:manual-link-org\"]]", performer_statement.reload.cache

    performer_statement.update!(
      cache: "[\"Manually deleted\",\"Organization\",[\"Venue Org\",\"footlight:manual-link-org\"]]",
      status: "updated",
      status_origin: "manual_test"
    )

    export_after_delete = ExportArtsdataService.call(seedurl: website.seedurl)
    refute_includes export_after_delete, "manual-link-org"
  end

  private

  def create_statement_with_source!(website:, webpage:, property:, algorithm_value:, cache:, status:, language: nil, manual: false)
    source = Source.create!(
      website: website,
      property: property,
      algorithm_value: algorithm_value,
      selected: true,
      selected_by: "test",
      render_js: false,
      language: language
    )

    Statement.create!(
      webpage: webpage,
      source: source,
      cache: cache,
      status: status,
      status_origin: "test",
      cache_refreshed: 1.day.ago,
      cache_changed: 1.day.ago,
      selected_individual: true,
      manual: manual
    )
  end
end
