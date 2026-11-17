# Delivery credentials belong in environment configuration, never the DSL or
# browser options. Existing ActionMailer settings are untouched unless enabled.
if ENV["MONITORING_SMTP_ADDRESS"].present?
  Rails.application.config.action_mailer.delivery_method = :smtp
  Rails.application.config.action_mailer.raise_delivery_errors = true
  Rails.application.config.action_mailer.smtp_settings = {
    address: ENV.fetch("MONITORING_SMTP_ADDRESS"),
    port: ENV.fetch("MONITORING_SMTP_PORT", "587").to_i,
    domain: ENV["MONITORING_SMTP_DOMAIN"],
    user_name: ENV["MONITORING_SMTP_USERNAME"],
    password: ENV["MONITORING_SMTP_PASSWORD"],
    authentication: ENV.fetch("MONITORING_SMTP_AUTHENTICATION", "plain"),
    enable_starttls_auto: true,
    open_timeout: 10,
    read_timeout: 20
  }.compact
end
