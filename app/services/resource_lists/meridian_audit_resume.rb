# frozen_string_literal: true

require "digest"
require "json"
require "time"
require "uri"

module ResourceLists
  # A previous read-only audit may be resumed only while its successfully
  # captured evidence remains fresh and its exact source configuration still
  # matches. An abort/challenge receipt is never reusable as event evidence.
  class MeridianAuditResume
    Invalid = Class.new(StandardError)
    MAX_AGE_SECONDS = 1800
    MAX_REPORT_BYTES = 2 * 1024 * 1024
    MAX_PAGES = MeridianPager::MAX_PAGES
    ROOT = "https://meridiancentrepointe.com"
    PATHS = { "en" => "/en/events", "fr" => "/fr/evenements" }.freeze

    Result = Struct.new(:pages, :provenance, keyword_init: true)

    def self.call(path:, database:, website:, sources:, now: Time.current)
      raise Invalid, "Report too large or missing" unless File.file?(path) && File.size(path).between?(1, MAX_REPORT_BYTES)

      bytes = File.binread(path)
      report = JSON.parse(bytes)
      raise Invalid, "Expected a previous QA full live audit" unless
        report["input_mode"] == "live_full_bounded" &&
        report["website_selection"] == "unscheduled_qa_copy" &&
        report["inventory_authoritative"] == false &&
        report["read_only"] == true && report["database"] == database &&
        report.dig("website", "id") == website.id &&
        report.dig("website", "seedurl") == website.seedurl &&
        report.dig("website", "test_copy_of_website_id") == website.test_copy_of_website_id

      generated_at = Time.iso8601(report.fetch("generated_at"))
      age = now.to_f - generated_at.to_f
      raise Invalid, "Previous audit too old or dated in the future; run a fresh audit" unless age.between?(-30, MAX_AGE_SECONDS)
      raise Invalid, "Expected both language reports" unless report.fetch("pages").keys.sort == PATHS.keys.sort

      pages = PATHS.to_h do |lang, root_path|
        source = sources.fetch(lang)
        recorded_source = report.fetch("sources").fetch(lang)
        raise Invalid, "Selected #{lang} Source changed; run a fresh audit" unless
          recorded_source["source_id"] == source.fetch(:source_id) &&
          recorded_source["source_sha256"] == source.fetch(:source_sha256) &&
          recorded_source["render_js"] == source.fetch(:render_js)

        received = report.fetch("pages").fetch(lang)
        raise Invalid, "#{lang}: no first-page receipt" unless received.is_a?(Hash) && received.key?("0")
        first = received.fetch("0")
        raise Invalid, "#{lang}: missing terminal proof on first page" unless first.is_a?(Hash) &&
          first["status"].nil? && first["pager_last_page"].is_a?(Integer) &&
          first["pager_last_page"].between?(0, MAX_PAGES - 1)
        last = first["pager_last_page"]
        raise Invalid, "#{lang}: unexpected page number in report" unless received.keys.all? do |key|
          key.match?(/\A(?:0|[1-9]\d*)\z/) && key.to_i.between?(0, last)
        end

        usable = received.each_with_object({}) do |(number, row), hash|
          next if row["status"] == "blocked" # only this page may be retried
          raise Invalid, "#{lang} page #{number}: invalid prior receipt" unless
            row["status"].nil? && row["http"] == 200 && row["sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
            row["bytes"].is_a?(Integer) && row["bytes"].positive? &&
            row.dig("page_evidence", "page_validation_status") == "observed" &&
            row["source_id"] == source.fetch(:source_id) &&
            row["source_sha256"] == source.fetch(:source_sha256) &&
            row["source_render_js"] == source.fetch(:render_js) &&
            row["capture_mode"] == (source.fetch(:render_js) ? "rendered_native" : "live_http")
          expected_url = "#{ROOT}#{root_path}?page=#{number}"
          raise Invalid, "#{lang} page #{number}: URL changed" unless row["url"] == expected_url &&
            row["final_url"] == expected_url
          captured_at = Time.iso8601(row.fetch("captured_at"))
          raise Invalid, "#{lang} page #{number}: evidence expired" unless (now.to_f - captured_at.to_f).between?(-30, MAX_AGE_SECONDS)
          urls = row["urls"]
          raise Invalid, "#{lang} page #{number}: invalid extracted URLs" unless urls.is_a?(Array) && urls.any? &&
            urls.all? { |url| valid_event_url?(url, lang) } &&
            row["rejected_xpath_values"] == [] &&
            row["xpath_hits"].is_a?(Integer) && row["xpath_hits"] >= urls.size
          hash[number.to_i] = row.symbolize_keys.merge(reused_from_report: true)
        end
        raise Invalid, "#{lang}: first page is not usable" unless usable.key?(0)
        [lang, usable]
      end
      Result.new(pages: pages, provenance: {
        input: path, sha256: Digest::SHA256.hexdigest(bytes),
        generated_at: report.fetch("generated_at"), maximum_age_seconds: MAX_AGE_SECONDS,
        note: "Successful page receipts reused; this is NOT an atomic live capture."
      })
    rescue Errno::ENOENT, JSON::ParserError, TypeError, KeyError, ArgumentError => error
      raise Invalid, "Invalid previous audit: #{error.class}: #{error.message}"
    end

    def self.valid_event_url?(url, lang)
      uri = URI.parse(url)
      uri.scheme == "https" && uri.host == URI.parse(ROOT).host && uri.userinfo.nil? &&
        uri.port == 443 && uri.path.start_with?("/#{lang}/") &&
        uri.fragment.nil?
    rescue URI::InvalidURIError
      false
    end
    private_class_method :valid_event_url?
  end
end
