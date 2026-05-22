require "test_helper"

class WebpagesHelperTest < ActionView::TestCase
  test "webpages summary heading uses website scoped totals and filter labels" do
    website = Website.create!(
      name: "Helper webpage site",
      seedurl: "helper-webpage-site",
      graph_name: "https://example.org/helper-webpage-site",
      default_language: "en"
    )

    heading = webpages_index_summary_heading(
      website: website,
      visible_count: 1,
      filtered_count: 1,
      total_count: 7,
      filters: { publishable: "true" }
    )

    assert_equal "Showing 1 of 1 publishable webpages for Helper webpage site.", heading
  end

  test "webpages filter label falls back to matching for term filters" do
    assert_equal "matching", webpages_filter_label(term: "festival")
  end

  test "selected rdfs class id resolves named class filters" do
    assert_equal rdfs_classes(:one).id, webpages_selected_rdfs_class_id(rdfs_class: "Event")
    assert_nil webpages_selected_rdfs_class_id(rdfs_class: "Other")
  end
end
