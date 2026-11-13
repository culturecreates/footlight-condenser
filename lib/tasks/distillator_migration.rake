namespace :distillator do
  desc "Report Distillator migration readiness from local code and fixtures"
  task migration_status: :environment do
    status = Distillator::MigrationStatus.call

    status.fetch(:checks).each do |label, passed|
      puts "#{label}: #{passed ? 'pass' : 'fail'}"
    end

    bypasses = status.fetch(:legacy_bypasses)
    puts "Known remaining legacy bypasses: #{bypasses[:count]}"
    bypasses[:files].each do |file|
      puts " - #{file}"
    end
  end
end
