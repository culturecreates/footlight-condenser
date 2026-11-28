# frozen_string_literal: true

# Pure offline preview of two operator-recognized bilingual candidate pairs.
# Reads the QA baseline JSON, not Rails, Wringer or the live website.
# No database connection, import, RDF minting, or cached statement writes.
require "json"
require "optparse"

module MeridianMissingPairPreview
  ORIGINAL = "meridiancentrepointe-com"
  QA = "meridiancentrepointetest-com"
  BASE = "https://meridiancentrepointe.com"
  CANDIDATES = {
    "solitary_man" => {
      "en" => "#{BASE}/en/solitary-man-neil-diamond-postponed",
      "fr" => "#{BASE}/fr/solitary-man-neil-diamond-REPORTE"
    },
    "scaramouche" => {
      "en" => "#{BASE}/en/scaramouche-queen-tribute-postponed",
      "fr" => "#{BASE}/fr/scaramouche-hommage-queen-REPORTE"
    }
  }.freeze

  def self.call(report)
    raise "Expected the Meridian QA baseline" unless report.dig("website", "seedurl") == QA &&
      report.dig("website", "test_copy_of_website_id") && report["read_only"] == true
    missing = Array(report.fetch("missing_event_webpage_urls"))
    indexed = report.fetch("rl_entries").group_by { |row| row.fetch("url") }
    rows = CANDIDATES.map do |label, urls|
      details = urls.to_h do |lang, url|
        entries = indexed.fetch(url, [])
        rdf = entries.map { |row| row.fetch("rdf_uri") }.uniq
        ns = rdf.map { |id| ResourceLists::MeridianCacheIdentityDiagnostics.namespace(id,
          original_seedurl: ORIGINAL, qa_seedurl: QA) }.uniq
        [lang, { url: url, listed: entries.any?, missing_webpage: missing.include?(url),
          cached_rdf_uris: rdf, namespaces: ns, source_resource_lists: entries.map { |row| row.fetch("rl_id") }.uniq }]
      end
      { candidate: label, evidence: details,
        assessment: details.values.all? { |row| row[:listed] && row[:missing_webpage] } ?
          "candidate_needs_verified_cross_language_key" : "blocked_incomplete_baseline",
        identity_action: "none",
        note: "Name/URL resemblance is a candidate, NOT a verified shared event key." }
    end
    { database: report.fetch("database"), qa_website: QA, read_only: true,
      candidate_pairs: rows, verified_shared_keys: 0, minted_identifiers: 0,
      import_authorized: false,
      note: "Inspect trustworthy common event ID or linked translations in the source HTML before keying or minting." }
  end
end

baseline = nil
output = nil
OptionParser.new do |opts|
  opts.on("--baseline PATH") { |value| baseline = value }
  opts.on("--json PATH") { |value| output = value }
end.parse!(ARGV)
abort "Unexpected arguments" unless ARGV.empty?
abort "Provide --baseline PATH" unless baseline && File.file?(baseline)
abort "Refusing overwrite: #{output}" if output && File.exist?(output)
# Load a pure service file without connecting to Rails.
require_relative "../app/services/resource_lists/meridian_cache_identity_diagnostics"
result = MeridianMissingPairPreview.call(JSON.parse(File.read(baseline)))
result.fetch(:candidate_pairs).each do |row|
  puts "#{row[:candidate]}: #{row[:assessment]}"
  row.fetch(:evidence).each do |lang, evidence|
    puts "  #{lang.upcase} RL=#{evidence[:source_resource_lists].inspect} namespace=#{evidence[:namespaces].inspect} #{evidence[:url]}"
  end
end
puts "Verified common keys: 0; no RDF minting, import or changes"
if output
  File.write(output, JSON.pretty_generate(result) + "\n")
  puts "Saved #{output}"
end
