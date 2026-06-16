require "test_helper"

class Statements::ExtractedParityComparisonServiceTest < ActiveSupport::TestCase
  test "defaults to essential properties only and ignores non essential differences" do
    website, webpage = build_statement_compare_fixture
    essential_same = create_statement_compare_source(
      website: website,
      property: essential_property(1, "Essential title"),
      algorithm: "xpath=//title/text()"
    )
    essential_changed = create_statement_compare_source(
      website: website,
      property: essential_property(3, "Essential description"),
      algorithm: "xpath=//meta[@name='description']/@content"
    )
    essential_removed = create_statement_compare_source(
      website: website,
      property: essential_property(5, "Essential legacy note"),
      algorithm: "xpath=//div[@class='legacy-only']/text()"
    )
    essential_error = create_statement_compare_source(
      website: website,
      property: essential_property(13, "Essential fetched title"),
      algorithm: "url=$url + '?detail'; xpath=//title/text()"
    )
    non_essential = create_statement_compare_source(
      website: website,
      property: non_essential_property(21, "Non essential photo"),
      algorithm: "xpath=//img/@src"
    )

    [essential_same, essential_changed, essential_removed, essential_error, non_essential].each do |source|
      create_statement_compare_record(webpage: webpage, source: source)
    end

    result = nil
    Distillator::FetchCacheStore.expects(:fetch).never

    assert_no_difference("Statement.count") do
      assert_no_difference("Source.count") do
        assert_no_difference("Webpage.count") do
          assert_no_difference("Distillator::FetchCache.count") do
            assert_no_difference("Distillator::TransitionEvidence.count") do
              assert_no_difference("Distillator::RolloutEvent.count") do
                result = Statements::ExtractedParityComparisonService.call(
                  webpage: webpage,
                  default_language: website.default_language,
                  legacy_html: legacy_html,
                  condenser_html: condenser_html,
                  refresh_helper: StatementsHelper.build_refresh_proxy(cookies: {})
                )
              end
            end
          end
        end
      end
    end

    assert_equal [1, 3, 5, 13], result.property_ids
    assert_equal 4, result.sources_count
    assert_equal 1, result.counts[:same]
    assert_equal 0, result.counts[:added]
    assert_equal 1, result.counts[:removed]
    assert_equal 1, result.counts[:changed]
    assert_equal 1, result.counts[:extraction_errors]
    assert_equal ["Essential description"], result.groups[:changed].map { |row| row[:property_label] }
    assert_equal ["Essential legacy note"], result.groups[:removed].map { |row| row[:property_label] }
    assert_equal ["Essential fetched title"], result.groups[:extraction_errors].map { |row| row[:property_label] }
    assert_equal ["Essential title"], result.groups[:same].map { |row| row[:property_label] }
    assert_not_includes result.groups.values.flatten.map { |row| row[:property_label] }, "Non essential photo"
  end

  test "essential property difference is still reported" do
    website, webpage = build_statement_compare_fixture(suffix: "essential-reported")
    source = create_statement_compare_source(
      website: website,
      property: essential_property(3, "Essential description"),
      algorithm: "xpath=//meta[@name='description']/@content"
    )
    create_statement_compare_record(webpage: webpage, source: source)

    result = Statements::ExtractedParityComparisonService.call(
      webpage: webpage,
      default_language: website.default_language,
      legacy_html: legacy_html,
      condenser_html: condenser_html,
      refresh_helper: StatementsHelper.build_refresh_proxy(cookies: {})
    )

    assert_equal 1, result.counts[:changed]
    assert_equal "Essential description", result.groups[:changed].first[:property_label]
    assert_equal "Legacy description", result.groups[:changed].first[:legacy]
    assert_equal "Condenser description", result.groups[:changed].first[:condenser]
  end

  private

  def build_statement_compare_fixture(suffix: "parity-compare-site")
    website = Website.create!(
      name: "Parity compare site #{suffix}",
      seedurl: suffix,
      graph_name: "https://example.org/#{suffix}",
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

  def create_statement_compare_source(website:, property:, algorithm:)
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

  def create_statement_compare_record(webpage:, source:)
    Statement.create!(
      cache: "seeded cache",
      status: "ok",
      status_origin: "test",
      cache_refreshed: 1.hour.ago,
      cache_changed: 1.hour.ago,
      source: source,
      webpage: webpage,
      selected_individual: true
    )
  end

  def essential_property(id, label)
    Property.create!(
      id: id,
      label: label,
      value_datatype: "MyString",
      uri: "https://example.org/properties/#{id}",
      rdfs_class: rdfs_classes(:one)
    )
  end

  def non_essential_property(id, label)
    Property.create!(
      id: id,
      label: label,
      value_datatype: "MyString",
      uri: "https://example.org/properties/#{id}",
      rdfs_class: rdfs_classes(:one)
    )
  end

  def legacy_html
    <<~HTML
      <html>
        <head>
          <title>Shared Title</title>
          <meta name="description" content="Legacy description">
        </head>
        <body>
          <div class="legacy-only">Legacy note</div>
        </body>
      </html>
    HTML
  end

  def condenser_html
    <<~HTML
      <html>
        <head>
          <title>Shared Title</title>
          <meta name="description" content="Condenser description">
        </head>
        <body>
          <img src="https://cdn.example.org/poster.jpg">
        </body>
      </html>
    HTML
  end
end
