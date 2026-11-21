require "digest"
require "net/http"
require "uri"

module Distillator
  class WringerReachability
    def initialize(base_url: WringerEndpoint.current.legacy_lookup_base_url)
      @uri = URI.parse(base_url.to_s)
    rescue URI::InvalidURIError
      @uri = nil
    end

    def display_url
      @uri.origin if @uri.is_a?(URI::HTTP) && @uri.host.present? && !@uri.query && !@uri.fragment
    end

    def call
      return { label: "Missing or invalid Wringer URL" } unless display_url

      Rails.cache.fetch("wringer-reachability/#{Digest::SHA256.hexdigest(@uri.to_s)}", expires_in: 30.seconds) do
        probe
      end
    end

    private

    def probe
      uri = @uri.dup
      # The list endpoint does not fetch upstream pages. Its HTTP status belongs to Wringer.
      uri.path = "#{uri.path.delete_suffix("/")}/websites.json"
      uri.query = "per_page=1"
      request = Net::HTTP::Get.new(uri)
      if uri.user
        request.basic_auth(URI::DEFAULT_PARSER.unescape(uri.user), URI::DEFAULT_PARSER.unescape(uri.password.to_s))
      end

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: 2, read_timeout: 2, write_timeout: 2, max_retries: 0) do |http|
        http.request(request)
      end
      label = response.is_a?(Net::HTTPSuccess) ? "Reachable" : "Responded (HTTP #{response.code})"
      { label: label }
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError
      { label: "Unreachable" }
    rescue Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError
      { label: "Invalid response" }
    end
  end
end
