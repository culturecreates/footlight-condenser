# frozen_string_literal: true

# Bounded, read-only collection of known ?page=N calendar URLs for local QA.
# It collects evidence; it does NOT infer a complete calendar or run imports.
#
# bundle exec ruby script/resource_list_numbered_probe.rb \
#   'https://hector-charland.com/programmation-spectacles?page=1' 5 \
#   /tmp/resource-list-trials/hector-charland
require "digest"
require "fileutils"
require "json"
require "net/http"
require "nokogiri"
require "time"
require "uri"

start = URI.parse(ARGV.fetch(0))
limit = Integer(ARGV.fetch(1), 10)
output = File.expand_path(ARGV.fetch(2))
abort "Expected HTTPS URL without credentials or fragment" unless
  start.scheme == "https" && start.host && !start.userinfo && !start.fragment
abort "Expected between 1 and 25 pages" unless (1..25).cover?(limit)
parameters = URI.decode_www_form(start.query.to_s)
abort "Expected exactly one numeric page=N parameter" unless
  parameters.count { |name, _| name == "page" } == 1 &&
  parameters.assoc("page").last.match?(/\A[1-9]\d*\z/)
first_page = parameters.assoc("page").last.to_i
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
      target = URI.join(uri.to_s, response.fetch("location"))
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
limit.times do |offset|
  number = first_page + offset
  url = start.dup
  url.query = URI.encode_www_form(parameters.map { |key, value| [key, key == "page" ? number.to_s : value] })
  requested_at = Time.now.utc.iso8601(6)
  response, final_url = fetch_page(url, start)
  content = response.body.to_s
  raise "Page #{number}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  raise "Page #{number}: not HTML (#{response['content-type']})" unless response["content-type"].to_s.match?(/html/i)
  raise "Page #{number}: oversized HTML response" if content.bytesize > 8_000_000
  doc = Nokogiri::HTML(content)
  hrefs = doc.xpath("//a[@href]").filter_map do |anchor|
    begin
      absolute = URI.join(final_url.to_s, anchor["href"])
      absolute if same_origin?(absolute, start)
    rescue URI::InvalidURIError
      nil
    end
  end
  prefix = "#{start.path.chomp('/')}/"
  events = hrefs.select { |link| link.path.start_with?(prefix) && link.path != start.path }.map(&:to_s).uniq
  pager = hrefs.select { |link| link.path == start.path &&
    URI.decode_www_form(link.query.to_s).any? { |key, _| key == "page" } }.map(&:to_s).uniq
  path = File.join(output, "page#{number}.html")
  File.binwrite(path, content)
  captures << { page: number, url: url.to_s, final_url: final_url.to_s,
    fetched_at: requested_at, status: response.code.to_i, bytes: content.bytesize,
    sha256: Digest::SHA256.hexdigest(content), event_link_count: events.length,
    sample_events: events.first(3), numbered_links: pager,
    next_link_observed: pager.include?(begin
      next_page = url.dup
      next_page.query = URI.encode_www_form(parameters.map { |key, value| [key, key == "page" ? (number + 1).to_s : value] })
      next_page.to_s
    end) }
  puts "page=#{number} status=#{response.code} event_urls=#{events.length} pager_links=#{pager.length} bytes=#{content.bytesize}"
  sleep(0.5) if offset < limit - 1
end

File.write(File.join(output, "probe.json"), JSON.pretty_generate(
  purpose: "read_only_numbered_pagination_diagnostic", not_completeness_proof: true,
  requested_pages: limit, captures: captures
))
puts "Saved #{File.join(output, 'probe.json')}"
