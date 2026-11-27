# frozen_string_literal: true

# Read-only trial on SAVED calendar HTML snapshots (no DB, network or jobs).
# Run: bundle exec ruby script/resource_list_capture_trial.rb /tmp/site/manifest.json
require "digest"
require "json"
require "nokogiri"
require "uri"
require_relative "../app/services/resource_lists/pagination_capture_proof"

abort "Usage: bundle exec ruby script/resource_list_capture_trial.rb manifest.json" unless ARGV.length == 1

manifest_path = File.expand_path(ARGV.first)
manifest = JSON.parse(File.read(manifest_path))
base_dir = File.dirname(manifest_path)
record_xpath = manifest.fetch("record_xpath")
next_xpath = manifest.fetch("next_xpath")
terminal_xpath = manifest.fetch("terminal_xpath")
pages = manifest.fetch("pages")
abort "pages must be a nonempty array" unless pages.is_a?(Array) && pages.any?

captures = pages.map.with_index do |page, index|
  path = File.expand_path(page.fetch("file"), base_dir)
  html = File.binread(path)
  document = Nokogiri::HTML(html)
  records = document.xpath(record_xpath)
  next_matches = document.xpath(next_xpath)
  terminal_matches = document.xpath(terminal_xpath)

  raise "Page #{index + 1}: expected at most one next link, got #{next_matches.size}" if next_matches.size > 1
  if next_matches.any? && !next_matches.first.is_a?(Nokogiri::XML::Attr)
    raise "Page #{index + 1}: next_xpath must select an href attribute, e.g. //a[@rel='next']/@href"
  end
  next_value = next_matches.first&.text.to_s.strip
  next_url = next_value.empty? ? nil : URI.join(page.fetch("url"), next_value).to_s
  # The terminal XPath must match an explicit source-page signal (e.g. disabled
  # next button). Absence of a next link alone is deliberately NOT evidence.
  terminal = "verified_no_next_link" if terminal_matches.any? && next_url.nil?

  {
    url: page.fetch("url"),
    status: "fetched",
    records: records.map { |node| Digest::SHA256.hexdigest(node.to_html) },
    next_url: next_url,
    terminal_evidence: terminal,
    fetched_at: page.fetch("fetched_at"),
    snapshot_sha256: Digest::SHA256.hexdigest(html)
  }
end

proof = ResourceLists::PaginationCaptureProof.call(
  start_url: manifest.fetch("start_url"), captures: captures,
  max_pages: manifest.fetch("max_pages", 50),
  max_skew_seconds: manifest.fetch("max_skew_seconds", 600)
)
puts JSON.pretty_generate(
  "status" => proof.status, "complete" => proof.complete?, "errors" => proof.errors,
  "pages" => captures.map { |p| p.slice(:url, :next_url, :terminal_evidence, :fetched_at, :snapshot_sha256)
    .merge(record_count: p.fetch(:records).size) },
  "total_records" => proof.record_count, "digest" => proof.digest
)
exit(proof.complete? ? 0 : 2)
