# frozen_string_literal: true

# Bounded, read-only collection of known ?page=N calendar URLs for local QA.
# It collects evidence; it does NOT infer a complete calendar or run imports.
#
# Default: at most 25 pages. Optional explicit limit: 1..50 pages.
# bundle exec ruby script/resource_list_numbered_probe.rb \
#   'https://hector-charland.com/programmation-spectacles?page=1' \
#   /tmp/resource-list-trials/hector-charland
# bundle exec ruby script/resource_list_numbered_probe.rb URL 5 OUTPUT_DIR
require "digest"
require "fileutils"
require "json"
require "net/http"
require "nokogiri"
require "time"
require "uri"
require_relative "../app/services/resource_lists/short_page_stop"
require_relative "../app/services/resource_lists/numbered_page_query"

abort "Usage: resource_list_numbered_probe.rb URL [MAX_PAGES] OUTPUT_DIR" unless (2..3).cover?(ARGV.length)
start = URI.parse(ARGV.fetch(0))
limit = ARGV.length == 3 ? Integer(ARGV.fetch(1), 10) : 25
output = File.expand_path(ARGV.last)
abort "Expected HTTPS URL without credentials or fragment" unless
  start.scheme == "https" && start.host && !start.userinfo && !start.fragment
abort "Expected MAX_PAGES between 1 and 50" unless (1..50).cover?(limit)
pagination = ResourceLists::NumberedPageQuery.new(start_url: start.to_s, parameter: ENV["PAGE_PARAMETER"])
first_page = pagination.first_page
FileUtils.mkdir_p(output)

def same_origin?(a, b)
  a.scheme == b.scheme && a.host == b.host && a.port == b.port
end

def fetch_page(uri, origin)
  4.times do
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
      open_timeout: 10, read_timeout: 25) do |http|
      request = Net::HTTP::Get.new(uri.request_uri,
        { "User-Agent" => "Footlight-ResourceList-QA/1.0 (read-only calendar diagnostics)",
          "Accept" => "text/html,application/xhtml+xml" })
      http.request(request)
    end
    if response.is_a?(Net::HTTPRedirection)
      raise "Redirect without Location" if response["location"].to_s.empty?
      target = URI.join(uri.to_s, response["location"].to_s)
      raise "Unsafe redirect to #{target}" unless target.scheme == "https" &&
        !target.userinfo && same_origin?(target, origin)
      uri = target
      next
    end
    return [response, uri]
  end
  raise "Too many redirects"
end

captures = []
previous_link_count = nil
previous_fingerprint = nil
stop_reason = nil
limit.times do |offset|
  number = first_page + offset
  url = URI.parse(pagination.url_for(number))
  requested_at = Time.now.utc.iso8601(6)
  response, final_url = fetch_page(url, start)
  unless pagination.matches_page?(final_url.to_s, page: number)
    raise "Page #{number}: final URL changed pagination key, path, or selected filters: #{final_url}"
  end
  content = response.body.to_s
  raise "Page #{number}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  raise "Page #{number}: not HTML (#{response['content-type']})" unless response["content-type"].to_s.match?(/html/i)
  raise "Page #{number}: oversized HTML response" if content.bytesize > 8_000_000
  doc = Nokogiri::HTML(content)
  all_link_count = doc.xpath("//a[@href]").length
  hrefs = doc.xpath("//a[@href]").filter_map do |anchor|
    begin
      absolute = URI.join(final_url.to_s, anchor["href"])
      absolute if same_origin?(absolute, start)
    rescue URI::InvalidURIError
      nil
    end
  end
  # Without an explicit site-specific XPath we cannot distinguish event links
  # from navigation/category links. Keep the count diagnostic, not authoritative.
  event_xpath = ENV["EVENT_LINK_XPATH"]
  events = if event_xpath.to_s.strip.empty?
    []
  else
    doc.xpath(event_xpath).filter_map do |node|
      begin
        raw = node.is_a?(Nokogiri::XML::Attr) ? node.value : node["href"]
        next if raw.to_s.strip.empty?
        link = URI.join(final_url.to_s, raw)
        link.to_s if same_origin?(link, start)
      rescue URI::InvalidURIError
        nil
      end
    end.uniq
  end
  pager = hrefs.select { |link| link.path == start.path &&
    URI.decode_www_form(link.query.to_s).any? { |key, _| key == pagination.parameter } }.map(&:to_s).uniq
  path = File.join(output, "page#{number}.html")
  File.binwrite(path, content)
  captures << { page: number, url: url.to_s, final_url: final_url.to_s,
    fetched_at: requested_at, status: response.code.to_i, bytes: content.bytesize,
    sha256: Digest::SHA256.hexdigest(content), all_link_count: all_link_count,
    event_link_count: events.length,
    sample_events: events.first(3), numbered_links: pager,
    event_link_xpath: event_xpath, title: doc.at_xpath("//title")&.text.to_s.strip,
    challenge_hint: !!(doc.at_xpath("//title")&.text.to_s.match?(/just a moment|attention required|access denied|verify you are human|checking your browser/i) ||
      doc.at_css("#challenge-stage, #challenge-form, [id^='cf-chl-']")),
    next_link_observed: pager.any? { |link| pagination.matches_page?(link.to_s, page: number + 1) } }
  short_page = previous_link_count && ResourceLists::ShortPageStop.stop?(
    previous_count: previous_link_count, current_count: all_link_count)
  same_content = previous_fingerprint == Digest::SHA256.hexdigest(content)
  captures.last[:short_page_stop] = !!short_page
  captures.last[:repeated_content] = !!same_content
  puts "page=#{number} status=#{response.code} all_links=#{all_link_count} candidate_event_urls=#{events.length} " \
    "pager_links=#{pager.length} bytes=#{content.bytesize} challenge_hint=#{captures.last[:challenge_hint]} short_page_stop=#{!!short_page} repeated_content=#{!!same_content}"
  if captures.last[:challenge_hint]
    stop_reason = "challenge_page_detected"
    break
  end
  if same_content
    stop_reason = "repeated_content"
    break
  end
  if short_page
    stop_reason = "heuristic_short_page"
    break
  end
  previous_fingerprint = Digest::SHA256.hexdigest(content)
  previous_link_count = all_link_count
  sleep(0.5) if offset < limit - 1
end

stop_reason ||= "max_pages_reached"
File.write(File.join(output, "probe.json"), JSON.pretty_generate(
  purpose: "read_only_numbered_pagination_diagnostic", not_completeness_proof: true,
  max_pages: limit, page_parameter: pagination.parameter, pages_fetched: captures.size, stop_reason: stop_reason,
  verified_completeness: false, captures: captures
))
puts "stop_reason=#{stop_reason} pages_fetched=#{captures.size} complete=UNVERIFIED"
puts "Saved #{File.join(output, 'probe.json')}"
