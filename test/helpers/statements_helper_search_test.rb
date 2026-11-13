require "test_helper"

class StatementsHelperSearchTest < ActionView::TestCase
  tests StatementsHelper

  test "expected_classes_for splits comma separated classes" do
    assert_equal ["Place", "VirtualLocation"], expected_classes_for("Place, VirtualLocation")
  end

  test "expected_classes_for preserves organization fallback to person" do
    assert_equal ["Organization", "Person"], expected_classes_for("Organization")
  end

  test "search_for_uri searches every expected class and deduplicates uri hits" do
    property = OpenStruct.new(expected_class: "Place, VirtualLocation")
    current_webpage = OpenStruct.new(rdf_uri: "http://current.example/resource")

    expects(:search_everywhere).with("Main Hall", "Place", current_webpage).returns(
      ["Main Hall", "Place", ["Main Hall", "http://example.org/place-1"], ["Current", "http://current.example/resource"]]
    )
    expects(:search_everywhere).with("Main Hall", "VirtualLocation", current_webpage).returns(
      ["Main Hall", "VirtualLocation", ["Main Hall", "http://example.org/place-1"], ["Main Hall Stream", "http://example.org/place-2"]]
    )

    assert_equal(
      [
        "Main Hall",
        "Place",
        ["Main Hall", "http://example.org/place-1"],
        ["Main Hall Stream", "http://example.org/place-2"]
      ],
      search_for_uri("Main Hall", property, current_webpage)
    )
  end
end
