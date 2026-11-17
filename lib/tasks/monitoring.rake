namespace :footlight do
  desc "Send one daily digest of explicitly flagged, unresolved DSL errors (optional monitoring mailbox)"
  task monitoring_digest: :environment do
    puts "Monitoring digest: #{Monitoring::DailyDigest.call}"
  end
end
