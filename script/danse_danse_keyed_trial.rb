# frozen_string_literal: true

# Read-only keyed extraction from contemporaneous saved FR/EN calendar HTML.
# DANSE_EN_HTML=path1,path2 DANSE_FR_HTML=path1,path2 \
#   bin/rails runner script/danse_danse_keyed_trial.rb /tmp/keyed-manifest.json
# Never use stale/noncontemporaneous pagination as completeness evidence.
require "json"

output = ARGV.first or abort "Usage: rails runner script/danse_danse_keyed_trial.rb /tmp/keyed-manifest.json"
abort "Refusing overwrite: #{output}" if File.exist?(output)
seedurl = ENV.fetch("SHADOW_SITE_SEEDURL", "dansedanse-ca")
site = Website.find_by!(seedurl: seedurl)
root = "https://www.dansedanse.ca"
streams = {}
inputs = {}
{
  "en" => {env: "DANSE_EN_HTML", path: "/en/shows", category: "Show"},
  "fr" => {env: "DANSE_FR_HTML", path: "/fr/spectacles", category: "Spectacle"}
}.each do |language, config|
  files = ENV.fetch(config.fetch(:env)) { abort "Missing #{config.fetch(:env)}" }.split(",").map(&:strip)
  abort "No HTML files for #{language}" if files.empty? || files.any?(&:empty?)
  item_xpath = "//div[contains(@class,'section--listing-spectacles__container')]" \
    "//div[contains(concat(' ',normalize-space(@class),' '),' block--spectacle ')]" \
    "[.//div[contains(@class,'block--spectacle__title--info--category')]/span[normalize-space(.)='#{config.fetch(:category)}']]"
  streams[language] = files.flat_map do |path|
    result = ResourceLists::KeyedCalendarExtractor.call(html: File.read(path), base_url: root + config.fetch(:path),
      item_xpath: item_xpath, url_xpath: "./a[1]/@href", key_xpath: "./a[1]/@href", key_mode: :url_last_segment)
    abort "Invalid #{language} extraction in #{path}: #{result.errors.inspect}" unless result.valid?
    result.records
  end
  inputs[language] = files
end

alignment = ResourceLists::KeyedCalendarAlignment.call(streams: streams)
abort "Invalid alignment: #{alignment.errors.inspect}" if alignment.status == "invalid"
urls = alignment.pairs.flat_map { |pair| pair.urls.values.compact }
existing = site.webpages.event_pages.where(url: urls).pluck(:url, :rdf_uri).to_h
conflicts = alignment.pairs.filter_map do |pair|
  uris = pair.urls.values.filter_map { |url| existing[url] }.uniq
  {key: pair.key, urls: pair.urls, rdf_uris: uris} if uris.size > 1
end
missing = alignment.pairs.filter_map do |pair|
  absent = pair.urls.reject { |_, url| existing.key?(url) || url.nil? }
  {key: pair.key, missing: absent, urls: pair.urls} if absent.any?
end
old_list = Statement.joins(:webpage).where(source_id: 1340, webpages: { website_id: site.id })
  .order(cache_refreshed: :desc, id: :desc).limit(1).pick(:cache)
old_urls = old_list ? JSON.parse(old_list) : []
abort "Prior Source #1340 cache is not a JSON array" unless old_urls.is_a?(Array)
new_urls = alignment.pairs.filter_map { |pair| pair.urls["en"] if pair.urls.values.none?(&:nil?) }
manifest = {
  seedurl: seedurl, inputs: inputs,
  status: conflicts.any? ? "rdf_uri_conflict" : alignment.complete? ? "ready_for_review" : "incomplete_translations",
  alignment_digest: alignment.digest, pair_count: alignment.pairs.size,
  unmatched_translation_keys: alignment.unmatched.map(&:key),
  conflicts: conflicts, currently_missing_webpages: missing,
  current_en_source_id: 1340,
  removed_vs_source_1340: old_urls.uniq - new_urls.uniq,
  added_vs_source_1340: new_urls.uniq - old_urls.uniq,
  pairs: alignment.pairs.map { |pair| {key: pair.key, urls: pair.urls,
    existing_rdf_uri: pair.urls.values.filter_map { |url| existing[url] }.uniq.first} }
}
File.write(output, JSON.pretty_generate(manifest))
puts "Keys=#{alignment.pairs.size}; conflicts=#{conflicts.size}; incomplete=#{alignment.unmatched.size}; new candidate URLs=#{missing.size}"
puts "EN source #1340 difference: -#{manifest[:removed_vs_source_1340].size} +#{manifest[:added_vs_source_1340].size}"
puts "Saved #{output} without database changes"
abort "Alignment blocked by conflicts/missing translations" unless alignment.complete? && conflicts.empty?
