module Monitoring
  class DailyDigest
    TIME_ZONE = "America/Toronto".freeze

    def self.call
      setting = MonitoringSetting.current
      setting.with_lock do
        today = Time.current.in_time_zone(TIME_ZONE).to_date
        return :disabled if setting.mailbox.blank?
        return :already_sent if setting.last_digest_on == today
        week = today.beginning_of_week(:monday)
        pulse_due = setting.weekly_pulse_enabled? && (setting.last_pulse_week_on.nil? || setting.last_pulse_week_on < week)
        issues = MonitoringIssue.open_issues.order(:seedurl, :source_id, :id).to_a
        return :empty if issues.empty? && !pulse_due
        raise "Set MONITORING_EMAIL_FROM before sending monitoring email" if ENV["MONITORING_EMAIL_FROM"].blank?

        # The database lock serializes concurrent scheduler calls. Persist the
        # date only after delivery succeeds, so delivery failures remain visible
        # to the job runner and can be retried. No per-statement mail jobs.
        if pulse_due
          MonitoringMailer.weekly(setting.mailbox, issues, today).deliver_now
          setting.update!(last_digest_on: today, last_pulse_week_on: week)
          :pulse_sent
        else
          MonitoringMailer.daily(setting.mailbox, issues, today).deliver_now
          setting.update!(last_digest_on: today)
          :sent
        end
      end
    end
  end
end
