require "test_helper"

class MonitoringControllerTest < ActionDispatch::IntegrationTest
  setup { Monitoring::Recorder.failure(statements(:one), error: "Audience mapping stale", notify: "daily") }

  test "monitoring shows issue context and diagnostics with email disabled" do
    get monitoring_path, params: { seedurl: "all" }
    assert_response :success
    assert_select ".harmonized-table-filters label", count: 2
    assert_select ".monitoring-table tbody tr", count: 1 do
      assert_select "th a[href='#{website_path(statements(:one).webpage.website)}']"
      assert_select "td strong", text: "DSL error"
      assert_select ".monitoring-table__time time[datetime]"
      assert_select ".operator-status", text: "Open"
      assert_select "details:not([open]) .monitoring-message", text: "Audience mapping stale"
      assert_select "a.operator-editor__button[href='#{statement_path(statements(:one))}']", text: "Inspect statement"
    end
  end

  test "a blocked fetch links to its cache and a historical issue with deleted records stays readable" do
    attributes = MonitoringIssue.first.attributes.except("id", "created_at", "updated_at")
    url = "https://example.org/blocked#event"
    MonitoringIssue.create!(attributes.merge(fingerprint: "blocked", kind: "blocked_fetch",
      url: url, message: "Blocked at #{url}. <script>example</script>", property_name: nil,
      statement_id: nil, source_id: 0))
    MonitoringIssue.create!(attributes.merge(fingerprint: "retired", seedurl: "retired-site",
      website_name: "Retired site", statement_id: 0, source_id: 0, resolved_at: Time.current))

    get monitoring_path, params: { status: "open" }
    assert_response :success
    assert_select ".monitoring-table td strong", text: "Blocked fetch"
    assert_select ".monitoring-table a[href='#{distillator_cache_index_path(term: url)}']", text: "Inspect fetch cache"
    assert_select ".monitoring-message a[href='#{url}']"
    assert_select ".monitoring-message script", count: 0

    get monitoring_path, params: { seedurl: "retired-site", status: "resolved" }
    assert_response :success
    assert_select ".monitoring-table tbody th a", count: 0
    assert_select ".monitoring-table tbody th", /Retired site/
    assert_select ".operator-status", text: "Resolved"
    assert_select ".monitoring-table td span", text: "No linked record"
  end

  test "JSON supports site and resolution filters without exposing mailbox" do
    MonitoringSetting.current.update!(mailbox: "private@example.org")
    get monitoring_path(format: :json), params: { seedurl: "all", status: "open" }
    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal 1, payload["issues"].size
    assert_equal 100, payload.dig("pagination", "per_page")
    assert_not_includes response.body, "private@example.org"
    get monitoring_path(format: :json), params: { seedurl: "unknown-site" }
    assert_empty JSON.parse(response.body)["issues"]
    Monitoring::Recorder.success(statements(:one))
    get monitoring_path(format: :json), params: { seedurl: "all", status: "resolved" }
    assert_equal 1, JSON.parse(response.body)["issues"].size
  end

  test "pagination caps results at 100" do
    attrs = MonitoringIssue.first.attributes.except("id", "created_at", "updated_at")
    100.times { |i| MonitoringIssue.create!(attrs.merge("fingerprint" => "extra-#{i}")) }
    get monitoring_path(format: :json), params: { seedurl: "all", page: 2 }
    payload = JSON.parse(response.body)
    assert_equal 1, payload["issues"].size
    assert_equal 101, payload.dig("pagination", "total_entries")
    assert_equal 2, payload.dig("pagination", "total_pages")
  end
end
