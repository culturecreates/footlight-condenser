require "ipaddr"
require "resolv"
require "uri"

module Distillator
  class UrlSafetyPolicy
    Decision = Struct.new(:allowed, :reason, :message, :normalized_url, keyword_init: true) do
      def allowed?
        allowed
      end
    end

    BLOCKED_IPV4_RANGES = [
      "0.0.0.0/8",
      "10.0.0.0/8",
      "100.64.0.0/10",
      "127.0.0.0/8",
      "169.254.0.0/16",
      "172.16.0.0/12",
      "192.0.0.0/24",
      "192.0.2.0/24",
      "192.168.0.0/16",
      "198.18.0.0/15",
      "198.51.100.0/24",
      "203.0.113.0/24",
      "224.0.0.0/4",
      "240.0.0.0/4"
    ].map { |range| IPAddr.new(range) }.freeze

    BLOCKED_IPV6_RANGES = [
      "::/128",
      "::1/128",
      "fc00::/7",
      "fe80::/10",
      "ff00::/8"
    ].map { |range| IPAddr.new(range) }.freeze

    def self.check_url(url, resolver: Resolv)
      new(resolver: resolver).check_url(url)
    end

    def self.check_response(response, resolver: Resolv)
      new(resolver: resolver).check_response(response)
    end

    def initialize(resolver: Resolv)
      @resolver = resolver
    end

    def check_url(url)
      uri = parse_uri(url)
      return blocked(:invalid_url, "Invalid URL: #{url}") unless uri
      return blocked(:blocked_scheme, "Blocked URL scheme: #{uri.scheme}") unless %w[http https].include?(uri.scheme)
      return blocked(:missing_host, "Missing URL host: #{url}") if uri.host.blank?
      return blocked(:blocked_localhost, "Blocked localhost host: #{uri.host}") if localhost?(uri.host)

      check_host(uri.host, normalized_url: uri.to_s)
    end

    def check_response(response)
      Array(response[:redirect_chain]).each do |url|
        decision = check_url(url)
        return decision unless decision.allowed?
      end

      final_url = response[:final_url]
      return allowed(nil) if final_url.blank?

      check_url(final_url)
    end

    private

    attr_reader :resolver

    def check_host(host, normalized_url:)
      literal_ip = parse_ip(host)
      return check_ip(literal_ip, host, normalized_url: normalized_url) if literal_ip

      addresses = resolver.getaddresses(host)
      return blocked(:dns_resolution_failed, "Blocked URL host with no DNS resolution result: #{host}") if addresses.blank?

      addresses.each do |address|
        decision = check_ip(parse_ip(address), host, normalized_url: normalized_url)
        return decision unless decision.allowed?
      end

      allowed(normalized_url)
    rescue StandardError => error
      blocked(:dns_resolution_error, "Blocked URL host after DNS resolution error for #{host}: #{error.class}")
    end

    def check_ip(ip, host, normalized_url:)
      return blocked(:invalid_resolved_address, "Invalid resolved address for #{host}") unless ip

      ranges = ip.ipv4? ? BLOCKED_IPV4_RANGES : BLOCKED_IPV6_RANGES
      return blocked(:blocked_private_ip, "Blocked private or reserved address #{ip} for #{host}") if ranges.any? { |range| range.include?(ip) }

      allowed(normalized_url)
    end

    def parse_uri(url)
      URI.parse(url.to_s)
    rescue URI::InvalidURIError
      nil
    end

    def parse_ip(value)
      IPAddr.new(value)
    rescue IPAddr::InvalidAddressError
      nil
    end

    def localhost?(host)
      normalized = host.to_s.downcase
      normalized == "localhost" || normalized.end_with?(".localhost")
    end

    def allowed(normalized_url)
      Decision.new(allowed: true, reason: nil, message: nil, normalized_url: normalized_url)
    end

    def blocked(reason, message)
      Decision.new(allowed: false, reason: reason, message: message, normalized_url: nil)
    end
  end
end
