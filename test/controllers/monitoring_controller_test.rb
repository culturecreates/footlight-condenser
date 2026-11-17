require "test_helper"

class MonitoringControllerTest < ActionDispatch::IntegrationTest
  setup { Monitoring::Recorder.failure(statements(:one), error: "Audience mapping stale", notify: "daily") }

  test "monitoring is visible and escaped with email disabled" do
    get monitoring_path, params: { seedurl: "all" }
    assert_response :success
    assert_select "td", text: "Audience mapping stale"
    assert_select "a[href='#{statement_path(statements(:one))}']"
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
