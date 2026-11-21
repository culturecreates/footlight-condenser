require "test_helper"

class HarmonizedTableHeadersTest < ActiveSupport::TestCase
  test "events headers expose sortable title date and archive date" do
    assert_equal(
      [
        { label: "Title", sort_key: "title" },
        { label: "Date", sort_key: "date" },
        { label: "Archive date", sort_key: "archive_date" },
        { label: "Status" },
        { label: "Actions" }
      ],
      HarmonizedTableHeaders.events
    )
  end

  test "resources headers expose sortable rdf uri class name and archive date" do
    assert_equal(
      [
        { label: "Rdf uri", sort_key: "rdf_uri" },
        { label: "Class", sort_key: "rdfs_class_name" },
        { label: "Name", sort_key: "name" },
        { label: "Archive date", sort_key: "archive_date" },
        { label: "Actions" }
      ],
      HarmonizedTableHeaders.resources
    )
  end

  test "sources headers expose readable inventory columns" do
    assert_equal(
      [
        { label: "ID", sort_key: "id" },
        { label: "Property", sort_key: "property_id" },
        { label: "Label", sort_key: "label" },
        { label: "Algorithm value", sort_key: "algorithm_value" },
        { label: "Selected", sort_key: "selected" },
        { label: "Render JS", sort_key: "render_js" },
        { label: "Auto review", sort_key: "auto_review" },
        { label: "Last test", sort_key: "updated_at" },
        { label: "Actions" }
      ],
      HarmonizedTableHeaders.sources
    )
  end

  test "webpages headers support optional condenser cache column" do
    without_condenser = HarmonizedTableHeaders.webpages(show_distillator_cache_column: false)
    with_condenser = HarmonizedTableHeaders.webpages(show_distillator_cache_column: true)

    refute_includes without_condenser.map { |header| header[:label] }, "Condenser Cache"
    assert_includes with_condenser.map { |header| header[:label] }, "Condenser Cache"
    assert_includes with_condenser, { label: "Updated", sort_key: "updated_at" }
  end

  test "reports headers expose sortable event title cache archive date webpage id and rdf uri" do
    assert_equal(
      [
        { label: "Event title", sort_key: "event_title" },
        { label: "Cache", sort_key: "cache" },
        { label: "Webpage id", sort_key: "webpage_id" },
        { label: "Archive date", sort_key: "archive_date" },
        { label: "Rdf uri", sort_key: "rdf_uri" }
      ],
      HarmonizedTableHeaders.reports
    )
  end

  test "places headers expose sortable uri based_on linked name and linked uri" do
    assert_equal(
      [
        { label: "Event Series URI", sort_key: "rdf_uri" },
        { label: "Based on", sort_key: "based_on" },
        { label: "Class" },
        { label: "Linked Name", sort_key: "linked_name" },
        { label: "Linked URI", sort_key: "linked_uri" }
      ],
      HarmonizedTableHeaders.places
    )
  end

  test "properties headers expose sortable id class label datatype expected class and uri" do
    assert_equal(
      [
        { label: "ID", sort_key: "id" },
        { label: "Rdfs class", sort_key: "rdfs_class_id" },
        { label: "Label", sort_key: "label" },
        { label: "Value datatype", sort_key: "value_datatype" },
        { label: "Expected Class", sort_key: "expected_class" },
        { label: "Uri", sort_key: "uri" },
        { label: "Actions" }
      ],
      HarmonizedTableHeaders.properties
    )
  end

  test "rdfs classes headers expose sortable name" do
    assert_equal(
      [
        { label: "Name", sort_key: "name" },
        { label: "Actions" }
      ],
      HarmonizedTableHeaders.rdfs_classes
    )
  end

  test "statements headers support optional website column" do
    with_website = HarmonizedTableHeaders.statements(show_seedurl_col: true)
    without_website = HarmonizedTableHeaders.statements(show_seedurl_col: false)

    assert_equal "Website", with_website[1][:label]
    refute_includes without_website.map { |header| header[:label] }, "Website"
    assert_includes with_website, { label: "Cache", sort_key: "cache" }
    assert_includes with_website, { label: "Updated", sort_key: "updated_at" }
  end
end
