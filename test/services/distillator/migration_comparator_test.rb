require "test_helper"

class Distillator::MigrationComparatorTest < ActiveSupport::TestCase
  class ExportServiceStub
    def initialize(actual:, expected:)
      @actual = actual
      @expected = expected
    end

    def call(seedurl:)
      @actual.fetch(seedurl)
    end

    def production_equivalent(seedurl:)
      @expected.fetch(seedurl)
    end
  end

  test "compares all selected export-relevant statements and ignores trace metadata" do
    website, webpage = build_fixture("all-selected")
    create_source(website: website, property: property_fixture(21, "Non important but selected"), algorithm: "xpath=//meta[@name='non-important']/@content")
    create_source(
      website: website,
      property: property_fixture(22, "Trace payload"),
      algorithm: 'manual=seed;ruby=[{"value"=>"Same Value","trace"=>{"step"=>"legacy-only"},"timing"=>{"ms"=>12}}]'
    )

    result = Distillator::MigrationComparator.call(
      website: website,
      webpage: webpage,
      legacy_html: html_with(non_important: "Legacy value"),
      condenser_html: html_with(non_important: "Condenser value"),
      export_service: ExportServiceStub.new(
        actual: { website.seedurl => "{\"@id\":\"event:1\"}" },
        expected: { website.seedurl => "{\"@id\":\"event:1\"}" }
      )
    )

    assert_equal Distillator::MigrationComparator::DIFFERENT_VALUE, result.statement_verdict
    assert_nil result.export_verdict
    diff_entry = result.statement_artifacts.find { |entry| entry[:property_id] == 21 }
    trace_entry = result.statement_artifacts.find { |entry| entry[:property_id] == 22 }
    assert_equal Distillator::MigrationComparator::DIFFERENT_VALUE, diff_entry[:verdict]
    assert_equal "Legacy value", diff_entry[:legacy]
    assert_equal "Condenser value", diff_entry[:condenser]
    assert_equal Distillator::MigrationComparator::MATCH, trace_entry[:verdict]
    assert_equal({ "value" => "Same Value" }, trace_entry[:legacy])
    assert_equal({ "value" => "Same Value" }, trace_entry[:condenser])
  end

  test "when statements match it compares normalized export and skips fetch diagnostics" do
    website, webpage = build_fixture("export-gate")
    create_source(website: website, property: property_fixture(31, "Title"), algorithm: "xpath=//title/text()")

    result = Distillator::MigrationComparator.call(
      website: website,
      webpage: webpage,
      legacy_html: "<html><head><title>Shared Title</title></head></html>",
      condenser_html: "<html><head><title>Shared Title</title></head></html>",
      legacy_fetch: { status: :ok, body: "legacy", final_url: "https://example.org/legacy", redirect_chain: [], headers: { content_type: "text/html" } },
      condenser_fetch: { status: :ok, body: "condenser", final_url: "https://example.org/condenser", redirect_chain: [], headers: { content_type: "text/html" } },
      export_service: ExportServiceStub.new(
        actual: { website.seedurl => '{"updated_at":"2026-05-25T12:00:00Z","@id":"event:1"}' },
        expected: { website.seedurl => '{"@id":"event:1"}' }
      )
    )

    assert_equal Distillator::MigrationComparator::MATCH, result.statement_verdict
    assert_equal Distillator::MigrationComparator::MATCH, result.export_verdict
    assert_nil result.fetch_diagnostic_verdict
    assert_nil result.fetch_artifacts
  end

  test "when statements differ it skips export and records raw fetch diagnostics only" do
    website, webpage = build_fixture("fetch-diagnostic")
    create_source(website: website, property: property_fixture(41, "Title"), algorithm: "xpath=//title/text()")

    export_service = Object.new
    export_service.define_singleton_method(:call) { |seedurl:| raise "export should not run for #{seedurl}" }
    export_service.define_singleton_method(:production_equivalent) { |seedurl:| raise "export should not run for #{seedurl}" }

    result = Distillator::MigrationComparator.call(
      website: website,
      webpage: webpage,
      legacy_html: "<html><head><title>Legacy Title</title></head></html>",
      condenser_html: "<html><head><title>Condenser Title</title></head></html>",
      legacy_fetch: {
        status: :ok,
        http_code: 200,
        body: "<html>legacy</html>",
        final_url: "https://example.org/final",
        redirect_chain: ["https://example.org/start", "https://example.org/final"],
        headers: { content_type: "text/html" },
        wringer: { error_type: "ignored" }
      },
      condenser_fetch: {
        status: :ok,
        http_code: 200,
        body: "<html>condenser</html>",
        final_url: "https://example.org/final",
        redirect_chain: ["https://example.org/start", "https://example.org/final"],
        headers: { content_type: "text/html" },
        wringer: { error_type: "ignored" }
      },
      export_service: export_service
    )

    assert_equal Distillator::MigrationComparator::DIFFERENT_VALUE, result.statement_verdict
    assert_nil result.export_verdict
    assert_equal Distillator::MigrationComparator::DIFFERENT_VALUE, result.fetch_diagnostic_verdict
    assert_equal %i[body_digest body_length content_type final_url http_code redirect_chain status].sort,
                 result.fetch_artifacts[:legacy].keys.sort
    assert_equal "ok", result.fetch_artifacts[:legacy][:status]
    assert_equal 200, result.fetch_artifacts[:legacy][:http_code]
    assert_equal "https://example.org/final", result.fetch_artifacts[:legacy][:final_url]
    assert_equal ["https://example.org/start", "https://example.org/final"], result.fetch_artifacts[:legacy][:redirect_chain]
    assert_equal "text/html", result.fetch_artifacts[:legacy][:content_type]
  end

  test "classifies read only parse failures as parse errors" do
    website, webpage = build_fixture("parse-error")
    create_source(website: website, property: property_fixture(51, "Fetched title"), algorithm: "url=$url + '?detail'; xpath=//title/text()")

    result = Distillator::MigrationComparator.call(
      website: website,
      webpage: webpage,
      legacy_html: "<html><head><title>Legacy</title></head></html>",
      condenser_html: "<html><head><title>Condenser</title></head></html>",
      export_service: ExportServiceStub.new(
        actual: { website.seedurl => '{"@id":"event:1"}' },
        expected: { website.seedurl => '{"@id":"event:1"}' }
      )
    )

    assert_equal Distillator::MigrationComparator::PARSE_ERROR, result.statement_verdict
    assert_equal Distillator::MigrationComparator::PARSE_ERROR, result.statement_artifacts.first[:verdict]
    assert_nil result.export_verdict
  end

  private

  def build_fixture(suffix)
    website = Website.create!(
      name: "Migration comparator #{suffix}",
      seedurl: "migration-comparator-#{suffix}",
      graph_name: "https://example.org/migration-comparator-#{suffix}",
      default_language: "en"
    )
    webpage = Webpage.create!(
      url: "https://example.org/#{suffix}/event",
      language: "en",
      rdf_uri: "rdf:#{suffix}:event",
      rdfs_class: rdfs_classes(:one),
      website: website
    )

    [website, webpage]
  end

  def create_source(website:, property:, algorithm:)
    Source.create!(
      algorithm_value: algorithm,
      selected: true,
      selected_by: "test",
      language: "en",
      render_js: false,
      property: property,
      website: website
    )
  end

  def property_fixture(id, label)
    Property.create!(
      id: id,
      label: label,
      value_datatype: "MyString",
      uri: "https://example.org/properties/#{id}",
      rdfs_class: rdfs_classes(:one)
    )
  end

  def html_with(non_important:)
    <<~HTML
      <html>
        <head>
          <meta name="non-important" content="#{non_important}">
        </head>
        <body></body>
      </html>
    HTML
  end
end
