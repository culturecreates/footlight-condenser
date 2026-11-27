# frozen_string_literal: true

# Read-only rendered pagination diagnostic using Distillator's existing
# render_js=true path, NOT an independent HTTP crawler or a cache refresh.
#
# This calls the configured PhantomJS renderer and can consume paid API quota.
# It does not touch Webpages, Statements, FetchCache, or ResourceList imports.
#
# Usage:
#   bin/rails runner script/resource_list_rendered_probe.rb \
#     'https://www.chasse-galerie.ca/fr/calendrier?page=1&number_items=48' \
#     4 /tmp/resource-list-trials/chasse-rendered
#
# Optional: PAGE_PARAMETER=pag EVENT_LINK_XPATH='//a[contains(@class,"event")]/@href'
require "digest"
require "fileutils"
require "json"
require "nokogiri"
require "time"
require "uri"
require_relative "../app/services/resource_lists/numbered_page_query"
require_relative "../app/services/resource_lists/short_page_stop"
require_relative "../app/services/resource_lists/link_inventory"
require_relative "../app/services/resource_lists/ajax_pagination_shell"

abort "Usage: bin/rails runner script/resource_list_rendered_probe.rb URL [MAX_PAGES] OUTPUT_DIR" unless (2..3).cover?(ARGV.size)
start = ARGV.fetch(0)
limit = ARGV.size == 3 ? Integer(ARGV.fetch(1), 10) : 5
abort "MAX_PAGES must be 1..25 (rendered requests may cost money)" unless (1..25).cover?(limit)
abort "DISTILLATOR_RENDERER must be legacy_phantomjs for this probe" unless
  (ENV["DISTILLATOR_RENDERER"].to_s.empty? || ENV["DISTILLATOR_RENDERER"] == "legacy_phantomjs")
abort "PHANTOMJS_API_KEY is required; no unrendered fallback" if ENV["PHANTOMJS_API_KEY"].to_s.empty?

pagination = ResourceLists::NumberedPageQuery.new(start_url: start, parameter: ENV["PAGE_PARAMETER"])
output = File.expand_path(ARGV.last)
FileUtils.mkdir_p(output)

previous_count = nil
previous_links = nil
captures = []
stop_reason = "max_pages_reached"
event_xpath = ENV["EVENT_LINK_XPATH"].to_s
limit.times do |index|
  page = pagination.first_page + index
  url = pagination.url_for(page)
  # No cache store: explicit active native rendered fetch with existing
  # eligibility, SSRF guard, renderer config, metadata and abort semantics.
  result = Distillator::FetchService.fetch_result(url: url, render_js: true, mode: :internal)
  unless result[:status] == :ok && result[:body].is_a?(String)
    reason = result.dig(:wringer, :error_type).to_s
    abort "Page #{page}: rendered fetch failed (#{reason.empty? ? 'unknown' : reason}); no cache or inventory updated"
  end

  html = result[:body]
  doc = Nokogiri::HTML(html)
  links = doc.xpath("//a[@href]").map { |a| a["href"].to_s }
  count = links.size
  link_hash = ResourceLists::LinkInventory.fingerprint(links)
  shell = ResourceLists::AjaxPaginationShell.inspect(doc)
  event_links = if event_xpath.empty?
    []
  else
    doc.xpath(event_xpath).filter_map do |node|
      raw = node.is_a?(Nokogiri::XML::Attr) ? node.value : node["href"]
      next if raw.to_s.strip.empty?
      begin
        absolute = URI.join(url, raw)
        absolute.to_s if absolute.scheme == "https" && absolute.host == URI(url).host
      rescue URI::InvalidURIError
        nil
      end
    end.uniq
  end
  short_page = !previous_count.nil? && ResourceLists::ShortPageStop.stop?(
    previous_count: previous_count, current_count: count)
  repeated_links = !link_hash.nil? && previous_links == link_hash
  challenge = !!(doc.at_xpath("//title")&.text.to_s.match?(/just a moment|attention required|access denied|verify you are human/i) ||
    doc.at_css("#challenge-stage, #challenge-form, [id^='cf-chl-']"))

  File.binwrite(File.join(output, "page#{page}.html"), html)
  captures << {
    page: page, requested_url: url, all_link_count: count,
    event_link_count: event_links.size, sample_events: event_links.first(3),
    event_link_xpath: event_xpath.empty? ? nil : event_xpath,
    sha256: Digest::SHA256.hexdigest(html),
    link_inventory_sha256: link_hash,
    ajax_shell_only: shell.shell_only?, ajax_endpoint: shell.endpoint,
    challenge_hint: challenge, short_page_stop: !!short_page,
    repeated_links: repeated_links,
    fetch_path: result[:fetch_path],
    renderer: result.dig(:wringer, :signals, :renderer),
    fetch_backend: result.dig(:wringer, :signals, :fetch_backend),
    rendered_at: Time.now.utc.iso8601(6)
  }

  puts "page=#{page} rendered_links=#{count} events=#{event_links.size} ajax_shell=#{shell.shell_only?} " \
    "repeated_links=#{repeated_links} short_page_stop=#{!!short_page} fetch_path=#{result[:fetch_path]}"

  if challenge
    stop_reason = "challenge_page_detected"
    break
  elsif shell.shell_only?
    stop_reason = "ajax_shell_still_empty_after_render"
    break
  elsif repeated_links
    stop_reason = "repeated_link_inventory"
    break
  elsif short_page
    stop_reason = "heuristic_short_page"
    break
  end

  previous_count = count
  previous_links = link_hash
  sleep(0.5) if index < limit - 1
end

File.write(File.join(output, "probe.json"), JSON.pretty_generate(
  purpose: "read_only_rendered_resource_list_diagnostic",
  verified_completeness: false, page_parameter: pagination.parameter,
  max_pages: limit, pages_fetched: captures.size, stop_reason: stop_reason,
  captures: captures
))
puts "stop_reason=#{stop_reason} pages_fetched=#{captures.size} complete=UNVERIFIED"
puts "Saved #{File.join(output, 'probe.json')}"
