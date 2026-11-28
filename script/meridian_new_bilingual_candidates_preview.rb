# frozen_string_literal: true

# Read-only preview of Meridian's two bilingual candidate events. These
# operator-review candidates are NOT derived from equivalent slug keys.
# Missing shared event identity evidence must block automatic RDF minting.
require "json"
require "optparse"

module MeridianNewBilingualCandidatesPreview
  PAIRS = {
    "solitary-man" => {
      "en" => "https://meridiancentrepointe.com/en/solitary-man-neil-diamond-postponed",
      "fr" => "https://meridiancentrepointe.com/fr/solitary-man-neil-diamond-REPORTE"
    },
    "scaramouche" => {
      "en" => "https://meridiancentrepointe.com/en/scaramouche-queen-tribute-postponed",
      "fr" => "https://meridiancentrepointe.com/fr/scaramouche-hommage-queen-REPORTE"
    }
  }.freeze

  module_function

  def analyze(report:, existing:)
    raise "Wrong QA-copy website" unless report.dig("website", "seedurl") == "meridiancentrepointetest-com"
    rows = report.fetch("rl_entries")
    raise "Expected cached ResourceList entries" unless rows.is_a?(Array) && rows.all? { |r| r.is_a?(Hash) }
    report_urls = rows.map { |row| row.fetch("url") }
    candidates = PAIRS.map do |label, translations|
      observations = translations.transform_values do |url|
        discovered = rows.select { |row| row.fetch("url") == url }
        {
          url: url,
          rl_ids: discovered.map { |row| row.fetch("rl_id") }.uniq.sort,
          cached_rdf_uris: discovered.map { |row| row.fetch("rdf_uri") }.uniq.sort,
          existing_qa_rdf_uris: Array(existing[url]).uniq.sort,
          in_caches: report_urls.include?(url)
        }
      end
      existing_uris = observations.values.flat_map { |row| row.fetch(:existing_qa_rdf_uris) }.uniq
      state = if observations.values.any? { |v| !v.fetch(:in_caches) }
        "blocked_missing_cached_url"
      elsif existing_uris.length > 1
        "blocked_existing_identity_conflict"
      elsif existing_uris.one?
        "review_existing_identity"
      else
        "review_new_bilingual_pair"
      end
      { candidate: label, status: state, observations: observations,
        shared_event_key: nil, proposed_rdf_uri: nil,
        note: "Human-visible title/slug similarity is NOT a verified shared event key. No minting permitted." }
    end
    { database: report.fetch("database"), website: report.fetch("website"),
      status: "review_only", candidates: candidates, read_only: true,
      import_allowed: false, minting_allowed: false,
      evidence: "Stored ResourceList caches, not complete validated live inventory" }
  end
end

abort "Refusing production" if Rails.env.production?
input = nil
output = nil
OptionParser.new do |parser|
  parser.on("--baseline PATH") { |path| input = path }
  parser.on("--json PATH") { |path| output = path }
end.parse!(ARGV)
abort "Unexpected arguments" unless ARGV.empty?
abort "Missing --baseline" unless input && File.file?(input)
abort "Refusing overwrite" if output && File.exist?(output)
abort "Oversized report" unless File.size(input).between?(1, 4 * 1024 * 1024)
baseline = JSON.parse(File.binread(input))
connection = ActiveRecord::Base.connection
abort "Wrong database" unless connection.current_database == "footlight_condenser_dansedanse_qa" &&
  baseline["database"] == connection.current_database
result = nil
connection.transaction do
  connection.execute("SET TRANSACTION READ ONLY")
  original = Website.find_by!(seedurl: "meridiancentrepointe-com")
  qa = Website.where(test_copy_of_website_id: original.id).sole
  abort "Wrong QA copy" unless qa.seedurl == baseline.dig("website", "seedurl") && qa.id == baseline.dig("website", "id") &&
    qa.distillator_mode == "shadow" && !qa.refresh_scheduled?
  urls = MeridianNewBilingualCandidatesPreview::PAIRS.values.flat_map(&:values)
  events = qa.webpages.event_pages.where(url: urls).pluck(:url, :rdf_uri).group_by(&:first)
  existing = events.transform_values { |rows| rows.map(&:last) }
  result = MeridianNewBilingualCandidatesPreview.analyze(report: baseline, existing: existing)
end
puts "Meridian QA new-event pairing preview | READ-ONLY | review_required"
result.fetch(:candidates).each do |candidate|
  puts "#{candidate[:candidate]}: #{candidate[:status]}"
  candidate[:observations].each do |language, row|
    puts "  #{language} #{row[:url]} stored_uris=#{row[:cached_rdf_uris].inspect} existing=#{row[:existing_qa_rdf_uris].inspect}"
  end
end
puts "No RDF minting, import, or database mutation permitted."
if output
  File.write(output, JSON.pretty_generate(result) + "\n")
  puts "Saved #{output}"
end
