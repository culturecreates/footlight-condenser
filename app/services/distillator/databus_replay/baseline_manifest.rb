require "date"
require "digest"
require "json"
require "pathname"
require "time"
require "uri"

module Distillator
  class DatabusReplay
    class BaselineManifest
      attr_reader :body, :captured_at, :sha256, :wringer_url

      def initialize(path)
        path = Pathname.new(path).expand_path
        @directory = path.dirname.realpath
        @body = path.binread.freeze
        @sha256 = Digest::SHA256.hexdigest(@body)
        data = JSON.parse(@body)
        @captured_at = Time.iso8601(data.fetch("captured_at")).utc.iso8601(6)
        @wringer_url = http_url(data.fetch("wringer_url"), allow_query: false).delete_suffix("/")
        @exports = data.fetch("exports").to_h
        @api_inputs = data.fetch("api_inputs", {}).to_h
        raise ArgumentError, "Manifest needs at least one export" if @exports.empty?
        unless sites.all? { |seedurl| seedurl.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_-]*\z/) }
          raise ArgumentError, "Manifest contains an invalid website seedurl"
        end
      end

      def sites = @exports.keys

      def export(seedurl)
        entry = @exports.fetch(seedurl)
        date = entry.fetch("date")
        raise ArgumentError, "Export date must be YYYY-MM-DD" unless Date.iso8601(date).iso8601 == date

        { date: date, url: http_url(entry.fetch("url")), body: checked_file(entry) }
      end

      def production_sources(seedurl)
        entry = @exports.fetch(seedurl)["production_sources"]
        return unless entry

        timestamp = Time.iso8601(entry.fetch("captured_at")).utc.iso8601(6)
        bytes = checked_file(entry)
        raise ArgumentError, "Production source snapshot needs a JSON array" unless JSON.parse(bytes).is_a?(Array)

        { body: bytes, captured_at: timestamp, sha256: entry.fetch("sha256") }
      end

      def api_inputs
        @api_inputs.to_h do |url, entry|
          [http_url(url), { body: checked_file(entry), captured_at: entry.fetch("captured_at"),
            provenance: entry.fetch("provenance") }]
        end
      end

      private

      def checked_file(entry)
        name = entry.fetch("file")
        unless name.is_a?(String) && name.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/)
          raise ArgumentError, "Manifest files must be alongside the manifest"
        end
        path = @directory.join(name).realpath
        raise ArgumentError, "Manifest files must be alongside the manifest" unless path.dirname == @directory && path.file?

        bytes = path.binread
        unless Digest::SHA256.hexdigest(bytes) == entry.fetch("sha256")
          raise ArgumentError, "SHA-256 mismatch for manifest file #{name}"
        end

        bytes
      end

      def http_url(url, allow_query: true)
        uri = URI.parse(url)
        unless uri.is_a?(URI::HTTP) && uri.host.present? && !uri.userinfo && !uri.fragment && (allow_query || !uri.query)
          raise ArgumentError, "Manifest URLs must use HTTP(S) without credentials or fragments"
        end
        url
      end
    end
  end
end
