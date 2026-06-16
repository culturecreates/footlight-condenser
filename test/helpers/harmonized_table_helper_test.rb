require "test_helper"

class HarmonizedTableHelperTest < ActionView::TestCase
  tests HarmonizedTableHelper

  test "renders sortable header link" do
    @request.path_parameters = { controller: "distillator/cache", action: "index" }

    html = harmonized_sortable_header("normalized_url", "URI / Name", filters: {})

    assert_includes html, "URI / Name"
    assert_includes html, "sort=normalized_url"
    assert_includes html, "direction=asc"
  end

  test "toggles asc and desc" do
    @request.path_parameters = { controller: "distillator/cache", action: "index" }

    params[:sort] = "http_response_code"
    params[:direction] = "asc"
    ascending_html = harmonized_sortable_header("http_response_code", "HTTP", filters: {})

    params[:direction] = "desc"
    descending_html = harmonized_sortable_header("http_response_code", "HTTP", filters: {})

    assert_includes ascending_html, "direction=desc"
    assert_includes descending_html, "direction=asc"
  end

  test "preserves term advanced filters and per page" do
    @request.path_parameters = { controller: "distillator/cache", action: "index" }

    html = harmonized_sortable_header(
      "http_response_code",
      "HTTP",
      filters: {
        term: "needle",
        health: "healthy",
        http_response_code: "404",
        content_type: "json",
        per_page: "25"
      }
    )

    assert_includes html, "term=needle"
    assert_includes html, "health=healthy"
    assert_includes html, "http_response_code=404"
    assert_includes html, "content_type=json"
    assert_includes html, "per_page=25"
  end

  test "drops page when changing sort" do
    @request.path_parameters = { controller: "distillator/cache", action: "index" }

    html = harmonized_sortable_header("name", "Name", filters: { term: "needle", page: "4", per_page: "25" })

    assert_includes html, "term=needle"
    assert_includes html, "per_page=25"
    assert_not_includes html, "page=4"
  end

  test "marks active sorted column" do
    @request.path_parameters = { controller: "distillator/cache", action: "index" }
    params[:sort] = "name"
    params[:direction] = "asc"

    html = harmonized_sortable_header("name", "Name", filters: {})

    assert_includes html, "Name ↑"
    assert_includes html, 'class="is-active-sort"'
    assert_includes html, 'aria-current="true"'
  end
end
