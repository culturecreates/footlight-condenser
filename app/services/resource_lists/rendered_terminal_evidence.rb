# frozen_string_literal: true

require "digest"
require "json"
require "time"
require_relative "numbered_page_query"

module ResourceLists
  # Checks saved rendered-page receipts and DOM audit facts against an explicit
  # site-specific empty-page message. A candidate is NOT a verified ResourceList
  # inventory: this cannot verify the site's JavaScript, applied filters or RDF IDs.
  class RenderedTerminalEvidence
    Result = Struct.new(:status, :errors, :terminal_page, :observed_cards, :reported_total, :digest, keyword_init: true) do
      def terminal_candidate? = status == "terminal_candidate"
    end

    def self.call(manifest:, audit:, exact_empty_text:, max_skew_seconds: 600)
      new(manifest:, audit:, exact_empty_text:, max_skew_seconds:).call
    end

    def initialize(manifest:, audit:, exact_empty_text:, max_skew_seconds:)
      @manifest, @audit, @exact_empty_text, @max_skew_seconds = manifest, audit, exact_empty_text, max_skew_seconds
    end

    def call
      return invalid("invalid_input") unless @manifest.is_a?(Hash) && @audit.is_a?(Hash) &&
        @manifest["purpose"] == "read_only_rendered_resource_list_diagnostic" &&
        @audit[:purpose] == "offline_rendered_calendar_card_audit" &&
        @manifest["verified_completeness"] == false && @audit[:verified_completeness] == false
      return invalid("missing_explicit_empty_text") unless @exact_empty_text.is_a?(String) && !@exact_empty_text.strip.empty?
      return invalid("invalid_time_bound") unless @max_skew_seconds.is_a?(Numeric) && @max_skew_seconds >= 0

      captures, pages = @manifest["captures"], @audit[:pages]
      return invalid("invalid_capture_count") unless captures.is_a?(Array) && pages.is_a?(Array) &&
        captures.length >= 2 && captures.length == pages.length && @manifest["pages_fetched"] == captures.length &&
        @manifest["max_pages"].is_a?(Integer) && (1..25).cover?(@manifest["max_pages"]) &&
        captures.length <= @manifest["max_pages"]
      return invalid("probe_stopped_without_terminal_observation") unless @manifest["stop_reason"] == "heuristic_short_page"

      begin
        query = NumberedPageQuery.new(start_url: captures.first.fetch("requested_url"), parameter: @manifest["page_parameter"])
      rescue ArgumentError, KeyError
        return invalid("invalid_pagination_query")
      end

      errors, timestamps, counts = [], [], []
      captures.each_with_index do |receipt, index|
        page = pages[index]
        unless receipt.is_a?(Hash) && page.is_a?(Hash)
          errors << "invalid_page:#{index}"
          next
        end
        expected = query.first_page + index
        unless receipt["page"] == expected && page[:page] == expected &&
          receipt["requested_url"] == page[:requested_url] &&
          query.matches_page?(receipt["requested_url"], page: expected) &&
          receipt["requested_url"] == query.url_for(expected)
          errors << "broken_or_unfiltered_page_chain:#{index}"
        end
        unless receipt["fetch_path"].to_s == "native" && receipt["challenge_hint"] == false &&
          receipt["ajax_shell_only"] == false
          errors << "untrusted_rendered_fetch:#{index}"
        end
        unless receipt["sha256"].is_a?(String) && receipt["sha256"] == page[:html_sha256]
          errors << "snapshot_digest_mismatch:#{index}"
        end
        begin
          timestamps << Time.iso8601(receipt.fetch("rendered_at"))
        rescue ArgumentError, KeyError, TypeError
          errors << "invalid_render_time:#{index}"
        end
        count = Integer(page[:reported_items_found], exception: false)
        errors << "missing_reported_total:#{index}" unless count && count >= 0 && count.to_s == page[:reported_items_found].to_s
        counts << count

        unless page[:container_found] == true && page[:cards].is_a?(Array) &&
          page[:direct_elements] == page[:cards].size
          errors << "missing_or_inconsistent_container:#{index}"
          next
        end
        if index == captures.length - 1
          unless page[:cards].length == 1 && page[:cards].first[:tag] == "p" &&
            page[:cards].first[:raw_hrefs] == [] && page[:terminal_message] == @exact_empty_text &&
            page[:cards].first[:text] == @exact_empty_text
            errors << "missing_exact_empty_terminal:#{index}"
          end
        elsif page[:cards].empty? || page[:terminal_message] ||
          page[:cards].any? { |card| !card.is_a?(Hash) || !card[:raw_hrefs].is_a?(Array) || card[:raw_hrefs].empty? }
          errors << "incomplete_nonterminal_cards:#{index}"
        end
      end
      errors << "inconsistent_reported_totals" unless counts.all? { |count| count && count == counts.first }
      observed = pages[0...-1].sum { |page| page.is_a?(Hash) && page[:cards].is_a?(Array) ? page[:cards].length : 0 }
      errors << "reported_total_does_not_match_cards" if counts.first && counts.first != observed
      errors << "capture_freshness_skew" if timestamps.any? && timestamps.max - timestamps.min > @max_skew_seconds
      digest = Digest::SHA256.hexdigest(JSON.generate(captures.map { |row| row.is_a?(Hash) ? row.values_at("page", "requested_url", "sha256", "rendered_at") : row }))
      Result.new(status: errors.empty? ? "terminal_candidate" : "inconclusive", errors: errors,
        terminal_page: captures.last.is_a?(Hash) ? captures.last["page"] : nil,
        observed_cards: observed, reported_total: counts.first, digest: digest)
    end

    private

    def invalid(reason)
      Result.new(status: "inconclusive", errors: [reason], terminal_page: nil,
        observed_cards: 0, reported_total: nil, digest: nil)
    end
  end
end
