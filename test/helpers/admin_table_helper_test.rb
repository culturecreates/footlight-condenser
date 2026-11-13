require "test_helper"

class AdminTableHelperTest < ActionView::TestCase
  tests AdminTableHelper

  test "admin_sortable preserves filters and toggles direction" do
    @request.path_parameters = { controller: "distillator/cache", action: "index" }
    params[:sort] = "name"
    params[:direction] = "asc"

    html = admin_sortable("name", "Name", filters: { term: "needle" })

    assert_includes html, "term=needle"
    assert_includes html, "sort=name"
    assert_includes html, "direction=desc"
    assert_includes html, "Name ↑"
  end
end
