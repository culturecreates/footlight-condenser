require "test_helper"

class MonitoringRecorderTest < ActiveSupport::TestCase
  setup { @statement = statements(:one) }

  test "only explicitly flagged errors enter monitoring" do
    [nil, {}, {error: "ordinary failure"}, {error: "not enabled", notify: true}, {error: "not enabled", notify: "false"}].each do |payload|
      assert_no_difference("MonitoringIssue.count") { Monitoring::Recorder.failure(@statement, payload) }
    end
    assert_difference("MonitoringIssue.count", 1) do
      Monitoring::Recorder.failure(@statement, {"error" => "Audience mapping is stale", "notify" => "daily"})
    end
    issue = MonitoringIssue.last
    assert_equal @statement.webpage.website.seedurl, issue.seedurl
    assert_equal "Audience mapping is stale", issue.message
    assert_equal @statement.id, issue.statement_id
    assert_equal 1, issue.occurrences
    assert_nil issue.resolved_at
  end

  test "repeated errors group by statement and a successful refresh resolves them" do
    2.times { Monitoring::Recorder.failure(@statement, error: "stale", notify: "daily") }
    issue = MonitoringIssue.last
    assert_equal 2, issue.occurrences
    Monitoring::Recorder.success(@statement)
    assert issue.reload.resolved_at
    Monitoring::Recorder.failure(@statement, error: "failed again", notify: "daily")
    assert_nil issue.reload.resolved_at
    assert_equal 1, issue.occurrences
    assert_equal "failed again", issue.message
  end

  test "recording failure does not raise into ordinary refresh" do
    MonitoringIssue.stubs(:create_or_find_by!).raises(StandardError, "database unavailable")
    assert_nil Monitoring::Recorder.failure(@statement, error: "stale", notify: "daily")
  end
  test "a monitoring database error rolls back its savepoint without aborting caller work" do
    database_error = Object.new
    def database_error.to_s
      MonitoringIssue.connection.execute("SELECT 1 / 0")
    end
    Statement.transaction do
      assert_nil Monitoring::Recorder.failure(@statement, error: database_error, notify: "daily")
      assert Statement.exists?(@statement.id)
    end
  end

end
