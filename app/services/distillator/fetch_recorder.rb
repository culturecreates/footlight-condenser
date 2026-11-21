require "digest/sha1"
require "fileutils"
require "json"
require "time"

module Distillator
  class FetchRecorder
    def self.record(url:, response:)
      return unless ENV["RECORD_FETCH"].present?

      site = sanitize_site(ENV["FETCH_SITE"])
      digest = Digest::SHA1.hexdigest(url.to_s)
      dir = Rails.root.join("data", "migration_fixtures", site, "fetch")
      path = dir.join("#{digest}.json")
      return if File.exist?(path)

      FileUtils.mkdir_p(dir)
      payload = {
        url: url,
        recorded_at: Time.now.utc.iso8601,
        response: response
      }
      File.write(path, JSON.pretty_generate(payload))
    rescue StandardError => e
      Rails.logger.warn("[FetchRecorder] failed for #{url}: #{e.class}: #{e.message}")
    end

    def self.sanitize_site(raw)
      value = raw.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      value.present? ? value : "default"
    end
    private_class_method :sanitize_site
  end
end
