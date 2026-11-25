require "test_helper"

class MonitoringDailyDigestTest < ActiveSupport::TestCase
  setup do
    @setting = MonitoringSetting.current
    @setting.update!(mailbox: "monitoring@example.org", last_digest_on: nil, weekly_pulse_enabled: false)
    @previous_sender = ENV["MONITORING_EMAIL_FROM"]
    ENV["MONITORING_EMAIL_FROM"] = "condenser@example.org"
    ActionMailer::Base.deliveries.clear
    Monitoring::Recorder.failure(statements(:one), error: "Audience mapping stale", notify: "daily")
  end

  teardown { ENV["MONITORING_EMAIL_FROM"] = @previous_sender }

  test "one digest per Toronto calendar day across all sites and repeated calls" do
    Monitoring::Recorder.failure(statements(:two), error: "Another monitored error", notify: "daily")
    travel_to Time.utc(2026, 11, 18, 1) do
      assert_equal :sent, Monitoring::DailyDigest.call
      assert_equal Date.new(2026, 11, 17), @setting.reload.last_digest_on
      assert_equal :already_sent, Monitoring::DailyDigest.call
      assert_equal 1, ActionMailer::Base.deliveries.size
      mail = ActionMailer::Base.deliveries.first
      assert_equal ["monitoring@example.org"], mail.to
      assert_includes mail.subject, "2 monitored errors"
      assert_includes mail.body.decoded, "Audience mapping stale"
      assert_includes mail.body.decoded, "Another monitored error"
    end
    travel_to Time.utc(2026, 11, 18, 13) do
      assert_equal :sent, Monitoring::DailyDigest.call
      assert_equal 2, ActionMailer::Base.deliveries.size
    end
  end

  test "monitoring page remains usable with email disabled and resolved errors are omitted" do
    @setting.update!(mailbox: nil)
    assert_equal :disabled, Monitoring::DailyDigest.call
    @setting.update!(mailbox: "monitoring@example.org")
    Monitoring::Recorder.success(statements(:one))
    assert_equal :empty, Monitoring::DailyDigest.call
    assert_empty ActionMailer::Base.deliveries
    assert_nil @setting.reload.last_digest_on
  end

  test "a monitored ResourceList issue without a source appears in the existing digest" do
    page = webpages(:six)
    Monitoring::ResourceListIssue.observe("resource_list_refresh", website: page.website, page: page, at: Time.current,
      message: "Scheduled ResourceList refresh is overdue.", evidence: { last_verified_refresh_at: 1.day.ago })

    assert_equal :sent, Monitoring::DailyDigest.call
    body = ActionMailer::Base.deliveries.sole.body.decoded
    assert_includes body, "ResourceList refresh"
    assert_includes body, "Scheduled ResourceList refresh is overdue."
    assert_includes body, "Last verified ResourceList refresh"
  end

  test "failed delivery retains issues and permits retry" do
    delivery = mock("mail delivery")
    delivery.expects(:deliver_now).raises(Net::SMTPFatalError, "delivery failed")
    MonitoringMailer.expects(:daily).returns(delivery)
    assert_raises(Net::SMTPFatalError) { Monitoring::DailyDigest.call }
    assert_nil @setting.reload.last_digest_on
    assert_equal 1, MonitoringIssue.open_issues.count
  end

  test "sender must be configured before recording successful delivery" do
    ENV.delete("MONITORING_EMAIL_FROM")
    assert_raises(RuntimeError) { Monitoring::DailyDigest.call }
    assert_nil @setting.reload.last_digest_on
    assert_empty ActionMailer::Base.deliveries
  end
end
