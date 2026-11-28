# frozen_string_literal: true

# Offline, read-only comparison of two existing ResourceList Source DSL
# replay reports. No HTML extraction, DB access, network or import.
# bundle exec ruby script/resource_list_saved_dsl_pair_audit.rb PROBE_DIR
require "json"
require_relative "../app/services/resource_lists/saved_dsl_pair_parity"

abort "Usage: resource_list_saved_dsl_pair_audit.rb PROBE_DIR" unless ARGV.length == 1
dir = File.expand_path(ARGV.first)
urls = JSON.parse(File.binread(File.join(dir, "dsl-snapshot-replay-source-9102.json")))
uris = JSON.parse(File.binread(File.join(dir, "dsl-snapshot-replay-source-9098.json")))
result = ResourceLists::SavedDslPairParity.call(url_report: urls, uri_report: uris)
payload = {
  purpose: "shawinigan_offline_source_url_uri_pairing_audit",
  status: result.status, errors: result.errors, terminal_page: result.terminal_page,
  total_values: result.total_values, unique_urls: result.unique_urls,
  duplicate_occurrences: result.duplicate_occurrences, page_counts: result.page_counts,
  verified_completeness: false, last_good_parity_verified: false, artsdata_export_parity_verified: false
}
path = File.join(dir, "dsl-source-pair-audit.json")
File.binwrite(path, JSON.pretty_generate(payload))
puts "status=#{result.status} terminal_page=#{result.terminal_page || '-'} " \
  "occurrences=#{result.total_values} unique=#{result.unique_urls} duplicates=#{result.duplicate_occurrences} " \
  "errors=#{result.errors.length} last_good_parity=UNVERIFIED"
result.errors.each { |error| warn "  #{error}" }
puts "Saved #{path}"
exit(result.errors.empty? ? 0 : 2)
