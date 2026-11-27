# frozen_string_literal: true

# Analyze saved rendered-page HTML from resource_list_rendered_probe.rb.
# No HTTP calls, no PhantomJSCloud credits, no Rails DB writes or imports.
#
# bundle exec ruby script/resource_list_rendered_audit.rb \
#   /tmp/resource-list-trials/chasse-rendered/probe.json
require "json"
require "time"
require_relative "../app/services/resource_lists/rendered_card_audit"

manifest_path = File.expand_path(ARGV.fetch(0))
manifest = JSON.parse(File.read(manifest_path))
abort "Expected rendered probe manifest" unless manifest["purpose"] == "read_only_rendered_resource_list_diagnostic"
captures = manifest.fetch("captures")
abort "No saved pages" if captures.empty?

pages = captures.map do |capture|
  number = Integer(capture.fetch("page"))
  path = File.join(File.dirname(manifest_path), "page#{number}.html")
  abort "Missing HTML: #{path}" unless File.file?(path)
  {
    page: number,
    url: capture.fetch("requested_url"),
    html: File.binread(path)
  }
end
audit = ResourceLists::RenderedCardAudit.analyze(pages: pages)
audit[:generated_at] = Time.now.utc.iso8601
output = File.join(File.dirname(manifest_path), "rendered-card-audit.json")
File.write(output, JSON.pretty_generate(audit))

audit.fetch(:pages).each do |page|
  puts "page=#{page[:page]} direct_elements=#{page[:direct_elements]} " \
    "unique_raw_hrefs=#{page[:unique_raw_hrefs]} " \
    "reported_items_found=#{page[:reported_items_found].inspect} " \
    "possible_empty_placeholder=#{page[:possible_empty_placeholder]} " \
    "container_found=#{page[:container_found]}"
end

puts "unique_raw_hrefs_all_pages=#{audit[:total_unique_raw_hrefs]} " \
  "unique_absolute_hrefs_all_pages=#{audit[:total_unique_absolute_hrefs]}"
audit[:repeated_raw_hrefs_across_pages].each do |duplicate|
  puts "CROSS_PAGE_DUPLICATE href=#{duplicate[:href].inspect}"
  duplicate[:occurrences].each do |ref|
    puts "  page=#{ref[:page]} card=#{ref[:card]} text=#{ref[:text].inspect}"
  end
end
audit[:cards_without_links].each do |card|
  puts "NO_LINK page=#{card[:page]} card=#{card[:card_index]} " \
    "tag=#{card[:tag]} class=#{card[:css_class].inspect} text=#{card[:text].inspect}"
end
puts "complete=UNVERIFIED (DOM children and links do not prove event or terminal identity)"
puts "Saved #{output}"
