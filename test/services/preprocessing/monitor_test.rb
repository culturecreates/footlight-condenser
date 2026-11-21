require "test_helper"

class PreprocessingMonitorTest < ActiveJob::TestCase
  include PreprocessingTestSupport
  setup { build_preprocessing_fixture }

  test "fresh successful output does not hide stale inputs and ordinary DSL recovery cannot clear it" do
    @input.update_columns(cache_refreshed: 4.days.ago)
    run = queued_preprocessing_run
    Preprocessing::Runner.call(@policy.id, run.id)
    assert_equal "succeeded", run.reload.status
    stale = MonitoringIssue.open_issues.find_by!(kind: "stale_inputs", preprocessing_policy_id: @policy.id)
    assert_includes stale.message, @input.id.to_s
    assert_not MonitoringIssue.open_issues.where(kind: "stale_refresh", preprocessing_policy_id: @policy.id).exists?
    Monitoring::Recorder.success(@target)
    assert_nil stale.reload.resolved_at
    @input.update_columns(cache_refreshed: Time.current)
    Preprocessing::Monitor.call
    assert_nil stale.reload.resolved_at, "Fresh upstream data alone does not repair a result computed from stale inputs"
    run = Preprocessing::Dispatcher.dispatch(@policy, force: true)
    Preprocessing::Runner.call(@policy.id, run.id)
    assert stale.reload.resolved_at
  end

  test "target freshness uses refresh timestamp and missing input identity is visible" do
    @target.update_columns(cache_changed: Time.current)
    @input.destroy!
    Preprocessing::Monitor.call
    assert MonitoringIssue.open_issues.where(kind: "stale_refresh").exists?
    assert_includes MonitoringIssue.open_issues.find_by!(kind: "stale_inputs").message, "missing"
    assert @policy.reload.last_checked_at
  end

  test "repeated checks do not inflate occurrences and disabling policy resolves its issues" do
    Preprocessing::Monitor.call
    issue = MonitoringIssue.open_issues.find_by!(kind: "stale_refresh")
    Preprocessing::Monitor.call
    assert_equal 1, issue.reload.occurrences
    @policy.update!(enabled: false)
    Preprocessing::Monitor.call
    assert issue.reload.resolved_at
  end

  test "weekly pulse detects preprocessing staleness even if the refresh dispatcher stopped" do
    setting = MonitoringSetting.current
    setting.update!(mailbox: "monitor@example.org", weekly_pulse_enabled: true)
    previous_sender = ENV["MONITORING_EMAIL_FROM"]
    ENV["MONITORING_EMAIL_FROM"] = "condenser@example.org"
    ActionMailer::Base.deliveries.clear
    assert_equal :pulse_sent, Monitoring::DailyDigest.call
    assert_includes ActionMailer::Base.deliveries.last.body.decoded, "Required preprocessing statement"
  ensure
    ENV["MONITORING_EMAIL_FROM"] = previous_sender
  end
end
