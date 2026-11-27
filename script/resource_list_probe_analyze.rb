# frozen_string_literal: true

# Analyze a read-only numbered pagination probe using its SAVED HTML.
# No network, database writes, Source updates, or event import.
#
# bundle exec ruby script/resource_list_probe_analyze.rb \
#   /tmp/resource-list-trials/hector-charland/probe.json
# Optional for other sites: EVENT_LINK_XPATH='//.../@href' bundle exec ruby ...
require "json"
require_relative "../app/services/resource_lists/short_page_stop"
require "nokogiri"
require "set"
require "uri"

path = File.expand_path(ARGV.fetch(0))
report = JSON.parse(File.read(path))
captures = report.fetch("captures")
abort "Empty or invalid captures" unless captures.is_a?(Array) && captures.any?
first = URI.parse(captures.first.fetch("url"))
abort "Expected HTTP(S) calendar URL" unless %w[http https].include?(first.scheme) && first.host
calendar_path = first.path.delete_suffix("/")
prefix = "#{calendar_path}/"
event_xpath = ENV["EVENT_LINK_XPATH"].to_s.strip
event_xpath = "//a[@href]/@href" if event_xpath.empty?
explicit_xpath = ENV["EVENT_LINK_XPATH"].to_s.strip != ""

def same_origin?(url, base)
  url.scheme == base.scheme && url.host == base.host && url.port == base.port
end

seen = Hash.new { |hash, key| hash[key] = [] }
page_results = captures.map do |capture|
  number = Integer(capture.fetch("page"))
  html_path = File.join(File.dirname(path), "page#{number}.html")
  abort "Missing snapshot #{html_path}" unless File.file?(html_path)
  doc = Nokogiri::HTML(File.binread(html_path))
  page_uri = URI.parse(capture.fetch("final_url", capture.fetch("url")))
  urls = doc.xpath(event_xpath).filter_map do |node|
    raw = node.is_a?(Nokogiri::XML::Attr) ? node.value : node["href"]
    next if raw.to_s.strip.empty?
    begin
      uri = URI.join(page_uri.to_s, raw)
      next unless same_origin?(uri, first)
      next unless explicit_xpath || uri.path.start_with?(prefix)
      uri.fragment = nil
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end
  end.uniq
  urls.each { |url| seen[url] << number }

  # Identify numbered links from the actual saved HTML, not assumed 1..N URLs.
  pager_numbers = doc.xpath("//a[@href]/@href").filter_map do |attr|
    begin
      link = URI.join(page_uri.to_s, attr.value)
      next unless same_origin?(link, first) && link.path.delete_suffix("/") == calendar_path
      params = URI.decode_www_form(link.query.to_s)
      values = params.select { |key, _| key == "page" }.map(&:last)
      Integer(values.first, 10) if values.one? && values.first.match?(/\A[1-9]\d*\z/)
    rescue URI::InvalidURIError, ArgumentError
      nil
    end
  end.uniq.sort
  title = doc.at_xpath("//title")&.text.to_s.strip
  challenge = !!(title.match?(/just a moment|attention required|access denied|verify you are human|checking your browser/i) ||
    doc.at_css("#challenge-stage, #challenge-form, [id^='cf-chl-']"))
  {
    page: number, title: title, events: urls.size, pager_numbers: pager_numbers,
    next_link_observed: capture["next_link_observed"], challenge_hint: challenge,
    html_sha256: capture["sha256"]
  }
end

short_page_stop = page_results.each_cons(2).find do |previous, current|
  current[:page] == previous[:page] + 1 &&
    ResourceLists::ShortPageStop.stop?(previous_count: previous[:events], current_count: current[:events])
end
short_page_stop_page = short_page_stop&.last&.fetch(:page)

duplicate_urls = seen.select { |_, pages| pages.size > 1 }
last_page = page_results.last
observed_numbers = page_results.map { |row| row[:page] }
pager_max = page_results.flat_map { |row| row[:pager_numbers] }.max
# Only a clue. A disabled Next control, source-advertised total-pages value,
# or another independently validated terminal signal is needed for proof.
possible_tail = !last_page[:next_link_observed] && pager_max == last_page[:page] &&
  observed_numbers == (observed_numbers.first..last_page[:page]).to_a
result = {
  purpose: "saved_html_pagination_analysis", verified_completeness: false,
  short_page_threshold: 0.9, short_page_stop_page: short_page_stop_page,
  short_page_stop_is_authoritative: false,
  pages: page_results, unique_event_urls: seen.size,
  total_page_event_counts: page_results.sum { |row| row[:events] },
  duplicate_across_pages: duplicate_urls.size,
  duplicate_samples: duplicate_urls.first(20).map { |url, pages| { url: url, pages: pages } },
  possible_numbered_pager_tail: possible_tail,
  note: "A missing page-#{last_page[:page] + 1} anchor alone is not terminal proof. Review the site pagination contract."
}
output = File.join(File.dirname(path), "probe-analysis.json")
File.write(output, JSON.pretty_generate(result))
page_results.each do |row|
  puts "page=#{row[:page]} events=#{row[:events]} pager=#{row[:pager_numbers].join(',')} " \
    "next=#{row[:next_link_observed]} challenge=#{row[:challenge_hint]}"
end
puts "unique_event_urls=#{seen.size} duplicate_across_pages=#{duplicate_urls.size} " \
  "short_page_stop=#{short_page_stop_page || 'none'} possible_tail=#{possible_tail} complete=UNVERIFIED"
puts "Saved #{output}"
