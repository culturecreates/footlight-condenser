require "test_helper"

class HarmonizedTablePartialsTest < ActionDispatch::IntegrationTest
  setup do
    Distillator::FetchCache.delete_all
  end

  test "cache index renders harmonized table hooks" do
    create_cache
    Distillator::FetchCacheStore.expects(:fetch).never

    get distillator_cache_index_path

    assert_response :success
    assert_select ".harmonized-table-toolbar", 1
    assert_select ".harmonized-table-filters", 1
    assert_select ".harmonized-table-shell", 1
    assert_select ".harmonized-table-actions", minimum: 1
    assert_select ".harmonized-table-empty-state", 0
  end

  test "cache index renders harmonized empty state hook when no rows match" do
    Distillator::FetchCacheStore.expects(:fetch).never

    get distillator_cache_index_path, params: { term: "missing-row" }

    follow_redirect! if response.redirect?
    assert_response :success
    assert_select ".harmonized-table-shell", 1
    assert_select ".harmonized-table-empty-state", 1
  end

  test "table shell renders empty state when records are empty" do
    html = ApplicationController.render(
      partial: "shared/tables/table_shell",
      locals: {
        table_key: :properties,
        records: [],
        row_partial: "properties/harmonized_row",
        row_name: :property,
        headers: [{ label: "Properties" }],
        filters: {},
        pagination: nil,
        sort: nil,
        direction: nil,
        sortable_filters: {},
        empty_message: "No properties found."
      }
    )

    assert_includes html, "harmonized-table-empty-state"
    assert_includes html, "No properties found."
  end

  test "table shell renders rows using row_partial and row_name" do
    html = ApplicationController.render(
      partial: "shared/tables/table_shell",
      locals: {
        table_key: :properties,
        records: [properties(:one)],
        row_partial: "properties/harmonized_row",
        row_name: :property,
        headers: [{ label: "Properties" }],
        filters: {},
        pagination: nil,
        sort: nil,
        direction: nil,
        sortable_filters: {}
      }
    )

    assert_includes html, properties(:one).label
    refute_includes html, "harmonized-table-empty-state"
  end

  test "table shell handles nil pagination safely" do
    html = ApplicationController.render(
      partial: "shared/tables/table_shell",
      locals: {
        table_key: :properties,
        records: [properties(:one)],
        row_partial: "properties/harmonized_row",
        row_name: :property,
        headers: [{ label: "Properties" }],
        filters: {},
        pagination: nil,
        sort: "label",
        direction: "asc",
        sortable_filters: {}
      }
    )

    assert_includes html, "harmonized-table-shell"
  end

  test "table shell fails clearly when row_partial is missing" do
    error = assert_raises(ActionView::Template::Error) do
      ApplicationController.render(
        partial: "shared/tables/table_shell",
        locals: {
          table_key: :properties,
          records: [],
          row_name: :property,
          headers: [{ label: "Properties" }],
          filters: {},
          pagination: nil,
          sort: nil,
          direction: nil,
          sortable_filters: {}
        }
      )
    end

    assert_includes error.message, "requires :row_partial"
  end

  test "toolbar renders source quick filters when table_key is sources" do
    html = ApplicationController.render(
      partial: "shared/tables/toolbar",
      locals: {
        table_key: :sources,
        quick_filters: [{ label: "Website defaults", params: { seedurl: "one" } }],
        seedurl: "one"
      }
    )

    assert_includes html, "Website defaults"
    assert_includes html, "Clear filters"
    refute_includes html, "Layout:"
    refute_includes html, "Fetch URL"
  end

  test "toolbar renders cache controls only for cache table use" do
    html = ApplicationController.render(
      partial: "shared/tables/toolbar",
      locals: {
        preserved_index_params: {},
        refresh_ui_enabled: true,
        view_mode: "rich"
      }
    )

    assert_includes html, "Layout:"
    assert_includes html, "Fetch URL"
    assert_includes html, "Quick filters"
  end

  private

  def create_cache
    Distillator::FetchCache.create!(
      uri_key: CGI.escape("http://example.org/cached"),
      normalized_url: "http://example.org/cached",
      html: "<html>cached</html>",
      body: "<html>cached</html>",
      name: "Cached",
      scrape_date: Time.zone.now,
      successful_refresh: Time.zone.now,
      http_response_code: 200,
      headers: {},
      signals: { "network_status" => "ok", "transport_success" => true, "content_success" => true, "content_type" => "html" },
      hints: [],
      redirect_chain: []
    )
  end
end
