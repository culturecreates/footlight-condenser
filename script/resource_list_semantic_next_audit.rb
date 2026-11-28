# frozen_string_literal: true

# Offline, read-only pager navigation audit of numbered probe snapshots.
# Does not request pages, extract event links, execute the DSL, import, or archive.
# bundle exec ruby script/resource_list_semantic_next_audit.rb /tmp/resource-list-trials/shawinigan-culture
require "digest"
require "json"
require "nokogiri"
require "uri"
require_relative "../app/services/resource_lists/numbered_page_url"
require_relative "../app/services/resource_lists/labeled_next_evidence"

abort "Usage: resource_list_semantic_next_audit.rb PROBE_DIRECTORY" unless ARGV.length == 1
dir = File.expand_path(ARGV.fetch(0))
probe = JSON.parse(File.read(File.join(dir, "probe.json")))
captures = probe.fetch("captures")
abort "No captured pages" if captures.empty?
query = ResourceLists::NumberedPageURL.build(start_url: captures.first.fetch("url"),
  parameter: probe.fetch("page_parameter"))

observations = captures.map do |capture|
  number = Integer(capture.fetch("page"))
  url = capture.fetch("final_url")
  abort "Unexpected final URL on page #{number}" unless query.matches_page?(url, page: number)

  path = File.join(dir, "page#{number}.html")
  html = File.binread(path)
  digest = Digest::SHA256.hexdigest(html)
  abort "Changed HTML snapshot on page #{number}" unless digest == capture.fetch("sha256")

  doc = Nokogiri::HTML(html)
  anchors = doc.css("a").map do |a|
    { href: a["href"], text: a.text, aria_label: a["aria-label"],
      title: a["title"], rel: a["rel"] }
  end
  evidence = ResourceLists::LabeledNextEvidence.call(
    anchors:, pagination: query, page: number, base_url: url)
  row = { page: number, url:, status: evidence.status,
    labeled_next_url: evidence.labeled_next_url,
    numbered_forward_link_seen: evidence.numbered_forward_link_seen,
    labeled_link_count: evidence.labeled_link_count,
    invalid_labeled_targets: evidence.invalid_labeled_targets }
  puts "page=#{number} labeled_next=#{evidence.status} forward=#{evidence.numbered_forward_link_seen} " \
    "target=#{evidence.labeled_next_url || '-'} conflicts=#{evidence.invalid_labeled_targets.length}"
  row
end

out = File.join(dir, "semantic-next-audit.json")
File.write(out, JSON.pretty_generate({
  purpose: "offline_read_only_semantic_next_diagnostic",
  extraction_source: "existing_dsl_only", verified_completeness: false,
  notes: "Missing or conflicting semantic Next links are not automatic terminal proof.",
  captures: observations
}))
puts "Saved #{out}; complete=UNVERIFIED"
