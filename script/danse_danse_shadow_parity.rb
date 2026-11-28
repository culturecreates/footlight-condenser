# frozen_string_literal: true

# Read-only commands; use separate copies of the SAME staging PostgreSQL DB.
# bin/rails runner script/danse_danse_shadow_parity.rb capture /tmp/baseline.json
# bin/rails runner script/danse_danse_shadow_parity.rb compare /tmp/baseline.json /tmp/report.json
require "json"

mode, path, output = ARGV
seedurl = ENV.fetch("SHADOW_SITE_SEEDURL", "dansedanse-ca")
abort "Usage: rails runner script/danse_danse_shadow_parity.rb [capture|compare] baseline.json [report.json]" unless %w[capture compare].include?(mode) && path

case mode
when "capture"
  abort "Refusing to overwrite existing baseline #{path}" if File.exist?(path)
  snapshot = Distillator::WebsiteShadowSnapshot.call(seedurl: seedurl)
  File.write(path, JSON.pretty_generate(snapshot))
  puts "Captured #{seedurl}: #{snapshot.fetch('webpages').size} webpages, #{snapshot.fetch('statements').size} selected statements"
  puts "Saved #{path} (no database mutations)"
when "compare"
  abort "Supply a different report path" if output.nil? || File.expand_path(path) == File.expand_path(output)
  baseline = JSON.parse(File.read(path))
  baseline_seedurl = baseline.fetch("website").fetch("seedurl")
  shadow = Distillator::WebsiteShadowSnapshot.call(seedurl: seedurl)
  # Comparing the original to its explicitly linked QA clone is allowed.
  # A different, unrelated site must never pass through identity normalization.
  if seedurl != baseline_seedurl && shadow["test_copy_origin_seedurl"] != baseline_seedurl
    abort "Snapshot site mismatch: #{seedurl} is not a QA copy of #{baseline_seedurl}"
  end
  result = Distillator::WebsiteShadowParity.call(baseline: baseline, shadow: shadow)
  File.write(output, JSON.pretty_generate({
    site: seedurl, status: result.status, differences: result.differences,
    graph: { added_count: result.graph_diff.added_count, removed_count: result.graph_diff.removed_count,
      same_count: result.graph_diff.same_count }
  }))
  puts "Shadow parity: #{result.status.upcase}; #{result.differences.keys.join(', ')}"
  puts "Graph +#{result.graph_diff.added_count} -#{result.graph_diff.removed_count}; saved #{output}"
  exit(result.passed? ? 0 : 1)
end
