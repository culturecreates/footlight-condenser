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

  desc "Record a completed production handoff using WEBSITE_ID, CUTOVER_AT, OPERATOR and EVIDENCE"
  task confirm_cutover: :environment do
    website = Website.find(ENV.fetch("WEBSITE_ID"))
    event = Distillator::VerifiedCutover.confirm!(
      website: website,
      completed_at: Time.iso8601(ENV.fetch("CUTOVER_AT")),
      actor: ENV.fetch("OPERATOR").strip,
      evidence: ENV.fetch("EVIDENCE").strip
    )
    puts "Recorded Condenser cutover for #{website.seedurl} (rollout event ##{event.id})."
  rescue KeyError, ArgumentError => error
    abort error.message
  end
end
