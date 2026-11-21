class MonitoringDigestJob < ApplicationJob
  queue_as :default

  def perform
    Monitoring::DailyDigest.call
  end
end
