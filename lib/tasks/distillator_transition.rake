namespace :distillator do
  namespace :transition do
    desc "Run second-production preflight checks (usage: bin/rails distillator:transition:preflight)"
    task preflight: :environment do
      result = Distillator::ProductionPreflight.call

      result.entries.each do |entry|
        puts entry.to_output
      end

      unless result.ok?
        puts "Preflight: FAILED"
        raise Distillator::ProductionPreflight::Failure, "Second-production preflight failed"
      end
    end

    desc "Record Fetch, Statements, and Export checks for a website (usage: bin/rails distillator:transition:check[website_id])"
    task :check, [:website_id] => :environment do |_task, args|
      website_id = args[:website_id] || ENV["website_id"] || ENV["WEBSITE_ID"]
      raise ArgumentError, "Missing website_id. Usage: bin/rails distillator:transition:check[website_id]" if website_id.blank?

      result = Distillator::TransitionCheckRunner.call(website: website_id)
      status = Distillator::TransitionCheck.call(website: result.website)

      puts "Fetch: #{operator_check_label(status.fetch)}"
      puts "Statements: #{operator_check_label(status.statements)}"
      puts "Export: #{operator_check_label(status.export)}"
      puts "Overall: #{operator_status_label(status.status)}"
      puts "Open: /distillator/shadow_report/#{result.website.id}"
    end
  end
end

def operator_check_label(status)
  {
    passed: "Passed",
    failed: "Failed",
    missing: "Missing",
    stale: "Stale"
  }.fetch(status.to_sym, status.to_s.humanize)
end

def operator_status_label(status)
  {
    ready: "Ready",
    review: "Needs review",
    blocked: "Blocked",
    not_checked: "Not checked"
  }.fetch(status.to_sym, status.to_s.humanize)
end
