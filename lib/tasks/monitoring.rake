namespace :footlight do
  desc "Send the due weekly monitoring pulse or daily error digest (optional monitoring mailbox)"
  task monitoring_digest: :environment do
    puts "Monitoring digest: #{Monitoring::DailyDigest.call}"
  end
end
