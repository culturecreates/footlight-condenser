# frozen_string_literal: true

# Read-only, schema-neutral JSON ResourceList endpoint diagnostic. No imports,
# source edits or completeness claims. Use a small set of pages as samples:
# bundle exec ruby script/resource_list_json_probe.rb \
#   'https://signelaval.com/api/events?count=12&lavalOnly=true&page=1&type=events' \
#   1,2,16 /tmp/resource-list-trials/signelaval-current-json
require "fileutils"
require "json"
require "net/http"
require "time"
require "uri"
require_relative "../app/services/resource_lists/numbered_page_query"
require_relative "../app/services/resource_lists/json_page_observation"

abort "Usage: resource_list_json_probe.rb PAGE_URL PAGES OUTPUT_DIR" unless ARGV.length == 3
start = URI.parse(ARGV.fetch(0))
pages = ARGV.fetch(1).split(",").map { |p| Integer(p, 10) }
abort "Expected 1–6 unique pages numbered between 0 and 50" unless
  (1..6).cover?(pages.length) && pages.uniq == pages && pages.all? { |p| p.between?(0, 50) }
pagination = ResourceLists::NumberedPageQuery.new(start_url: start.to_s, parameter: ENV["PAGE_PARAMETER"])
output = File.expand_path(ARGV.fetch(2))
FileUtils.mkdir_p(output)

def request_page(url, origin)
  requested = URI.parse(url)
  current = requested
  4.times do
    response = Net::HTTP.start(current.host, current.port, use_ssl: true,
      open_timeout: 10, read_timeout: 25) do |http|
      request = Net::HTTP::Get.new(current.request_uri, {
        "User-Agent" => "Footlight-ResourceList-QA/1.0 (read-only JSON probe)",
        "Accept" => "application/json"
      })
      http.request(request)
    end
    if response.is_a?(Net::HTTPRedirection)
      location = response["location"].to_s
      raise "Redirect without location" if location.empty?
      target = URI.join(current.to_s, location)
      unless target.scheme == "https" && target.host == origin.host && target.port == origin.port &&
        !target.userinfo && !target.fragment
        raise "Unsafe cross-origin or malformed redirect"
      end
      current = target
      next
    end
    return [response, current]
  end
  raise "Too many redirects"
end

observations = []
stop_reason = nil
pages.each do |page|
  url = pagination.url_for(page)
  captured_at = Time.now.utc.iso8601(6)
  begin
    response, final_url = request_page(url, start)
    body = response.body.to_s
    valid_final_url = pagination.matches_page?(final_url.to_s, page: page)
    observation = ResourceLists::JsonPageObservation.call(http_status: response.code.to_i,
      content_type: response["Content-Type"], body: body)
    status = valid_final_url ? observation.status : "inconclusive"
    errors = observation.errors.dup
    errors << "changed_effective_page_or_filters" unless valid_final_url
    File.binwrite(File.join(output, "page#{page}.response"), body) if body.bytesize <= ResourceLists::JsonPageObservation::MAX_BYTES
    observations << { page:, url:, effective_url: final_url.to_s, captured_at:,
      http_status: response.code.to_i, content_type: response["Content-Type"],
      status:, errors:, top_level: observation.top_level,
      top_keys: observation.top_keys, array_candidates: observation.arrays,
      response_sha256: observation.sha256, response_bytes: body.bytesize }
    puts "page=#{page} http=#{response.code} type=#{response['Content-Type']} " \
      "json=#{status} candidates=#{observation.arrays.length} errors=#{errors.join(',')}"
    unless errors.empty?
      stop_reason = "untrusted_response"
      break
    end
  rescue StandardError => e
    # Avoid publishing full URLs, response bodies or tokens in an error message.
    observations << { page:, url:, captured_at:, status: "inconclusive", errors: [e.class.name] }
    stop_reason = "fetch_failed"
    warn "page=#{page} fetch_failed=#{e.class}"
    break
  end
end
stop_reason ||= "sample_pages_inspected"
File.write(File.join(output, "probe.json"), JSON.pretty_generate({
  purpose: "read_only_json_page_schema_diagnostic", verified_completeness: false,
  start_url: start.to_s, requested_pages: pages, pages_fetched: observations.length,
  stop_reason:, captures: observations
}))
puts "stop_reason=#{stop_reason} complete=UNVERIFIED output=#{File.join(output, 'probe.json')}"
