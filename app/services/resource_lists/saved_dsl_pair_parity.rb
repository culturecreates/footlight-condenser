# frozen_string_literal: true

require "digest"
require "json"
require "uri"

module ResourceLists
  # Verify that the *existing DSL outputs* for a URL/URI Source pair are
  # positionally consistent. This does not extract events or assert last-good
  # inventory, Artsdata parity, or complete pagination.
  class SavedDslPairParity
    URL_SOURCE_ID = 9102
    URI_SOURCE_ID = 9098
    SEEDURL = "tourismeshawinigan-com".freeze
    Result = Struct.new(:status, :errors, :page_counts, :total_values, :unique_urls,
      :duplicate_occurrences, :terminal_page, keyword_init: true)

    def self.call(url_report:, uri_report:)
      new(url_report:, uri_report:).call
    end

    def initialize(url_report:, uri_report:)
      @urls, @uris = url_report, uri_report
    end

    def call
      errors = []
      errors << "url_source_wrong_label" unless @urls["source_id"] == URL_SOURCE_ID && @urls["property_label"] == "Webpage URL List"
      errors << "uri_source_wrong_label" unless @uris["source_id"] == URI_SOURCE_ID && @uris["property_label"] == "URI List"
      errors << "unexpected_website" unless @urls["website_seedurl"] == SEEDURL
      %w[status website_id website_seedurl terminal_page].each do |key|
        errors << "mismatched_#{key}" unless @urls[key] == @uris[key]
      end
      errors << "replay_not_successful" unless @urls["status"] == "dsl_replayed_parity_unverified"
      errors << "no_safety_evidence" unless [@urls, @uris].all? do |r|
        r["network_disabled"] == true && r["db_transaction_read_only"] == true &&
          r["verified_completeness"] == false && r["extraction_parity_verified"] == false
      end
      url_pages = @urls["pages"]
      uri_pages = @uris["pages"]
      errors << "invalid_pages" unless url_pages.is_a?(Array) && url_pages.any? &&
        uri_pages.is_a?(Array) && url_pages.length == uri_pages.length
      return failed(errors) if errors.any?

      values_seen = Hash.new(0)
      url_to_uri, uri_to_url = {}, {}
      counts = []
      url_pages.zip(uri_pages).each_with_index do |(u, r), page_index|
        number = u["page"]
        unless number.is_a?(Integer) && number == url_pages.first["page"] + page_index &&
          number == r["page"] && u["url"] == r["url"]
          errors << "mismatched_page_identity:#{number.inspect}"
          next
        end
        uv, rv = u["values"], r["values"]
        unless uv.is_a?(Array) && rv.is_a?(Array) && uv.length == rv.length &&
          u["count"] == uv.length && r["count"] == rv.length
          errors << "mismatched_values_count:#{number}"
          next
        end
        unless [[u, uv], [r, rv]].all? { |row, data| row["sha256"] == Digest::SHA256.hexdigest(JSON.generate(data)) }
          errors << "value_digest_mismatch:#{number}"
          next
        end
        counts << { page: number, count: uv.size }
        errors << "empty_page_values:#{number}" if uv.empty?
        errors << "duplicates_within_page:#{number}" unless uv.uniq.length == uv.length && rv.uniq.length == rv.length
        errors << "unsorted_page_values:#{number}" unless uv.sort == uv && rv.sort == rv
        uv.zip(rv).each_with_index do |(url, identifier), index|
          unless url.is_a?(String) && identifier.is_a?(String)
            errors << "non_string_pair:#{number}:#{index}"
            next
          end
          uri = URI.parse(url)
          slug = /^.*\/(.*)\/$/.match(url)&.[](1)
          unless uri.scheme == "https" && %w[tourismeshawinigan.com www.tourismeshawinigan.com].include?(uri.host) &&
            uri.path.start_with?("/evenements/") && uri.query.nil? && uri.fragment.nil? && slug && !slug.empty?
            errors << "invalid_event_url:#{number}:#{index}"
            next
          end
          expected = "footlight:#{@urls['website_seedurl']}_#{slug}"
          errors << "uri_mismatch:#{number}:#{index}" unless identifier == expected
          errors << "inconsistent_uri_for_url:#{number}:#{index}" if url_to_uri.key?(url) && url_to_uri[url] != identifier
          errors << "uri_collision:#{number}:#{index}" if uri_to_url.key?(identifier) && uri_to_url[identifier] != url
          url_to_uri[url] ||= identifier
          uri_to_url[identifier] ||= url
          values_seen[url] += 1
        rescue URI::InvalidURIError
          errors << "invalid_event_url:#{number}:#{index}"
        end
      end
      errors << "unexpected_terminal_page" unless counts.last && counts.last[:page] == @urls["terminal_page"]
      total = counts.sum { |p| p[:count] }
      errors << "summary_count_mismatch" unless [@urls, @uris].all? do |report|
        report["total_values"] == total && report["duplicate_values"] == total - values_seen.size
      end
      Result.new(status: errors.empty? ? "url_uri_pairing_verified_last_good_unverified" : "inconclusive",
        errors: errors.uniq, page_counts: counts, total_values: total, unique_urls: values_seen.size,
        duplicate_occurrences: total - values_seen.size, terminal_page: counts.last&.dig(:page))
    rescue KeyError, JSON::GeneratorError, ArgumentError, TypeError => e
      failed(["invalid_replay_report:#{e.class}"])
    end

    private

    def failed(errors)
      Result.new(status: "inconclusive", errors: errors, page_counts: [],
        total_values: 0, unique_urls: 0, duplicate_occurrences: 0, terminal_page: nil)
    end
  end
end
