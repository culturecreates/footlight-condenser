class MonitoringMailer < ApplicationMailer
  def daily(mailbox, issues, date)
    @issues = issues
    @date = date
    @monitoring_url = ENV["MONITORING_CONSOLE_URL"].presence
    site_count = issues.map(&:seedurl).uniq.size
    environment = Distillator::TransitionRuntime.staging? ? "staging" : Rails.env
    headline = if issues.size == 1
      "#{issues.first.website_name.presence || issues.first.seedurl}: #{issues.first.message}".tr("\r\n", " ").squish.first(150)
    else
      "#{issues.size} monitored errors across #{site_count} sites"
    end
    mail(to: mailbox, from: ENV.fetch("MONITORING_EMAIL_FROM"),
      subject: "[Condenser #{environment}] #{headline} — #{date}")
  end
end
