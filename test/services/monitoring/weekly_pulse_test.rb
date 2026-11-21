require "test_helper"

class MonitoringWeeklyPulseTest < ActionDispatch::IntegrationTest
  setup do
    @setting = MonitoringSetting.current
    @setting.update!(mailbox: "monitoring@example.org", weekly_pulse_enabled: true, last_digest_on: nil, last_pulse_week_on: nil)
    @previous_sender = ENV["MONITORING_EMAIL_FROM"]
    ENV["MONITORING_EMAIL_FROM"] = "condenser@example.org"
    ActionMailer::Base.deliveries.clear
  end

  teardown { ENV["MONITORING_EMAIL_FROM"] = @previous_sender }

  test "zero issue pulse sends once each Toronto calendar week" do
    travel_to Time.utc(2026, 11, 23, 1) do # Still Sunday November 22 in Toronto.
      assert_equal :pulse_sent, Monitoring::DailyDigest.call
      assert_equal Date.new(2026, 11, 16), @setting.reload.last_pulse_week_on
      assert_equal :already_sent, Monitoring::DailyDigest.call
      assert_equal 1, ActionMailer::Base.deliveries.size
      mail = ActionMailer::Base.deliveries.first
      assert_includes mail.subject, "Weekly monitoring pulse"
      assert_includes mail.subject, "0 open issues"
      assert_includes mail.body.decoded, "No open issues are currently flagged in Monitoring."
    end
    travel_to Time.utc(2026, 11, 23, 13) do
      assert_equal :pulse_sent, Monitoring::DailyDigest.call
      assert_equal Date.new(2026, 11, 23), @setting.reload.last_pulse_week_on
    end
    travel_to Time.utc(2026, 11, 24, 13) do
      assert_equal :empty, Monitoring::DailyDigest.call
      assert_equal 2, ActionMailer::Base.deliveries.size
    end
  end

  test "pulse includes the same open problems as Monitoring and replaces the daily digest" do
    Monitoring::Recorder.failure(statements(:one), error: "Audience map stale", notify: "daily")
    Monitoring::Recorder.failure(statements(:two), error: "Missing input", notify: "daily")
    Monitoring::Recorder.failure(statements(:three), error: "Resolved error", notify: "daily")
    Monitoring::Recorder.success(statements(:three))
    Monitoring::Recorder.failure(statements(:four), error: "Unflagged error")
    get monitoring_path(format: :json), params: { seedurl: "all", status: "open" }
    messages = JSON.parse(response.body).fetch("issues").map { |issue| issue.fetch("message") }
    assert_equal 2, messages.size

    travel_to Time.utc(2026, 11, 17, 14) do
      assert_equal :pulse_sent, Monitoring::DailyDigest.call
      assert_equal :already_sent, Monitoring::DailyDigest.call
      assert_equal 1, ActionMailer::Base.deliveries.size
      mail = ActionMailer::Base.deliveries.first
      messages.each { |message| assert_includes mail.body.decoded, message }
      assert_not_includes mail.body.decoded, "Resolved error"
      assert_not_includes mail.body.decoded, "Unflagged error"
      assert_includes mail.body.decoded, "Sites needing attention:"
    end
    travel_to Time.utc(2026, 11, 18, 14) do
      assert_equal :sent, Monitoring::DailyDigest.call
      assert_not_includes ActionMailer::Base.deliveries.last.subject, "Weekly monitoring pulse"
    end
  end

  test "disabling pulse or mailbox suppresses zero issue mail" do
    @setting.update!(weekly_pulse_enabled: false)
    assert_equal :empty, Monitoring::DailyDigest.call
    @setting.update!(weekly_pulse_enabled: true, mailbox: nil)
    assert_equal :disabled, Monitoring::DailyDigest.call
    assert_empty ActionMailer::Base.deliveries
    assert_nil @setting.reload.last_pulse_week_on
  end

  test "failed pulse delivery leaves both markers unchanged for retry" do
    delivery = mock("weekly delivery")
    delivery.expects(:deliver_now).raises(Net::SMTPFatalError, "delivery failed")
    MonitoringMailer.expects(:weekly).returns(delivery)
    assert_raises(Net::SMTPFatalError) { Monitoring::DailyDigest.call }
    assert_nil @setting.reload.last_pulse_week_on
    assert_nil @setting.last_digest_on
  end

  test "already sent daily email defers the first weekly pulse until another day" do
    travel_to Time.utc(2026, 11, 17, 14) do
      @setting.update!(last_digest_on: Date.new(2026, 11, 17))
      assert_equal :already_sent, Monitoring::DailyDigest.call
      assert_empty ActionMailer::Base.deliveries
      assert_nil @setting.reload.last_pulse_week_on
    end
    travel_to Time.utc(2026, 11, 18, 14) do
      assert_equal :pulse_sent, Monitoring::DailyDigest.call
      assert_equal 1, ActionMailer::Base.deliveries.size
    end
  end
end
