require 'test_helper'

class PlacesControllerTest < ActionDispatch::IntegrationTest
  test "places controller renders all supported legacy place cache shapes" do
    Places::IndexQuery.stubs(:call).returns(
      [
        { rdf_uri: "legacy:simple", based_on: "http://example.com/legacy/simple", place_class: "Place", linked_name: "Wednesday @ Salle Andre-Mathieu", linked_uri: "adr:salle-andre-mathieu" },
        { rdf_uri: "legacy:nested-a", based_on: "http://example.com/legacy/nested", place_class: "Place", linked_name: "Saturday @ Theatre des Muses", linked_uri: "http://example.com/muses" },
        { rdf_uri: "legacy:nested-b", based_on: "http://example.com/legacy/nested", place_class: "Place", linked_name: "Monday @ Theatre des Muses", linked_uri: "http://example.com/muses" },
        { rdf_uri: "legacy:json-string", based_on: "http://example.com/legacy/json-string", place_class: "Place", linked_name: "Main Hall", linked_uri: "" },
        { rdf_uri: "legacy:raw-string", based_on: "http://example.com/legacy/raw-string", place_class: "Place", linked_name: "Fallback Hall", linked_uri: "" }
      ]
    )

    get places_url(seedurl: websites(:one).seedurl)

    assert_response :success
    assert_includes @response.body, "Wednesday @ Salle Andre-Mathieu"
    assert_includes @response.body, "Saturday @ Theatre des Muses"
    assert_includes @response.body, "Monday @ Theatre des Muses"
    assert_includes @response.body, "Main Hall"
    assert_includes @response.body, "Fallback Hall"
  end

  test "places index renders harmonized table shell and sortable headers" do
    get places_url(seedurl: websites(:one).seedurl)

    assert_response :success
    assert_select ".harmonized-table-shell", 1
    assert_select 'th a[href*="sort=rdf_uri"]'
  end

  test "places index falls back safely for invalid sort and direction" do
    get places_url(seedurl: websites(:one).seedurl, sort: "bogus", direction: "sideways")

    assert_response :redirect
    assert_redirected_to places_url(seedurl: websites(:one).seedurl)
  end

  test "places index renders empty state" do
    website = Website.create!(
      name: "empty place website",
      seedurl: "empty-place-website",
      graph_name: "http://example.com/empty-place-website",
      default_language: "en",
      distillator_mode: "legacy"
    )

    get places_url(seedurl: website.seedurl)

    assert_response :success
    assert_select ".harmonized-table-empty-state", 1
  end

  test "places index does not fetch" do
    assert_read_only_page_does_not_fetch

    get places_url(seedurl: websites(:one).seedurl)

    assert_response :success
  end

  private

  def assert_read_only_page_does_not_fetch
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never
  end
end
