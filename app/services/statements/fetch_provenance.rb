require "digest"
require "addressable/uri"

module Statements
  class FetchProvenance
    MAX_DEPENDENCIES = 20

    def self.document(url, result)
      metadata = result[:wringer].to_h.with_indifferent_access
      body = result[:body]
      {
        identity: Digest::SHA256.hexdigest(url.to_s),
        host: host_for(url),
        cache_id: metadata[:cache_id],
        fingerprint: (Digest::SHA256.hexdigest(body) if body.is_a?(String)),
        source_fetched_at: metadata[:source_fetched_at],
        backend: metadata[:backend] || metadata.dig(:signals, :fetch_backend),
        http_status: result[:http_code],
        result: result[:status].to_s,
        usage: { true => "cached", false => "fetched" }[metadata[:cache_hit]]
      }.compact
    end

    def self.host_for(url)
      Addressable::URI.parse(url.to_s).host
    rescue Addressable::URI::InvalidURIError
      nil
    end
    private_class_method :host_for

    def initialize
      @dependencies = []
    end

    def observe(document, primary:)
      if primary
        @primary = document
      elsif !@dependencies.include?(document)
        @dependencies.size < MAX_DEPENDENCIES ? @dependencies << document : @truncated = true
      end
    end

    def opaque_dependencies!
      @opaque_dependencies = true
    end

    def snapshot(result:, recorded_at:)
      { "recorded_at" => recorded_at.utc.iso8601(6), "result" => result,
        "primary" => @primary, "dependencies" => @dependencies,
        "dependencies_incomplete" => (@truncated || @opaque_dependencies || false) }.compact
    end
  end
end
