require 'test_helper'

class ReportsControllerTest < ActionDispatch::IntegrationTest
  test "reports source does not fetch" do
    assert_read_only_page_does_not_fetch

    get source_reports_url(source_id: sources(:one).id)

    assert_response :success
  end

  test "reports source renders harmonized table shell filters and sortable headers" do
    get source_reports_url(source_id: sources(:one).id)

    assert_response :success
    assert_select ".harmonized-table-shell", 1
    assert_select ".harmonized-table-filters", 1
    assert_select 'form[action="/reports/source"][method="get"]', 1
    assert_select 'input[type="submit"][value="Apply filters"]', 1
    assert_select 'a', text: "Reset filters"
    assert_select 'th a[href*="sort=event_title"]'
    assert_select 'th a[href*="sort=archive_date"]'
  end

  test "reports source preserves active filters in sort links" do
    get source_reports_url(source_id: sources(:one).id), params: { startDate: "2018-01-01", endDate: "2030-01-01", per_page: "10" }

    assert_response :success
    assert_sort_link_preserves_filters(
      label: "Event title",
      sort_key: "event_title",
      params: {
        startDate: "2018-01-01",
        endDate: "2030-01-01",
        per_page: "10"
      }
    )
  end

  test "reports source falls back safely for invalid sort and direction" do
    get source_reports_url(source_id: sources(:one).id), params: { sort: "bogus", direction: "sideways" }

    assert_response :redirect
    assert_redirected_to source_reports_url(source_id: sources(:one).id)
  end

  test "reports source renders empty state" do
    source = Source.create!(
      algorithm_value: "report-empty",
      selected: true,
      selected_by: "Distillator",
      language: "en",
      render_js: false,
      property: properties(:one),
      website: websites(:one)
    )

    get source_reports_url(source_id: source.id)

    assert_response :success
    assert_select ".harmonized-table-empty-state", 1
  end

  test "reports source view renders rows from report_rows" do
    get source_reports_url(source_id: sources(:one).id)

    assert_response :success
    row = Reports::IndexQuery.call(
      filters: { source_id: sources(:one).id.to_s },
      sort: Reports::IndexQuery::DEFAULT_SORT,
      direction: Reports::IndexQuery::DEFAULT_DIRECTION,
      page: 1,
      per_page: Reports::IndexQuery::DEFAULT_PER_PAGE
    ).first

    assert row.present?
    assert_includes @response.body, row[:event_title].to_s if row[:event_title].present?
    assert_includes @response.body, row[:cache].to_s
    assert_includes @response.body, row[:rdf_uri].to_s
  end

  test "reports source does not assign legacy filtered hashes" do
    get source_reports_url(source_id: sources(:one).id)

    assert_response :success
    assert_nil assigns(:filtered_event_titles)
    assert_nil assigns(:filtered_archive_dates)
    assert_nil assigns(:filtered_event_uris)
    assert_nil assigns(:statements)
  end

  private

  def assert_read_only_page_does_not_fetch
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never
  end
end
