# frozen_string_literal: true

require "digest"
require "json"
require "time"
require "uri"
require "nokogiri"

module ResourceLists
  # Offline evidence for a site-specific JSON/HTML AJAX pagination sequence.
  # A candidate is not verified ResourceList completeness or archival authority:
  # recorded requests alone do not attest to network provenance or RDF identity.
  class AjaxPaginationEvidence
    Result = Struct.new(:status, :errors, :terminal_page, :card_occurrences, :unique_event_urls, :digest,
                        keyword_init: true) do
      def terminal_candidate? = status == "terminal_candidate"
    end

    def self.call(captures:, endpoint:, calendar_url:, category_id:, category_label:, exact_empty_text:,
                  expected_total: nil, max_pages: 25, max_skew_seconds: 600)
      new(captures:, endpoint:, calendar_url:, category_id:, category_label:, exact_empty_text:,
          expected_total:, max_pages:, max_skew_seconds:).call
    end

    def initialize(captures:, endpoint:, calendar_url:, category_id:, category_label:, exact_empty_text:,
                   expected_total:, max_pages:, max_skew_seconds:)
      @captures, @endpoint, @calendar_url = captures, endpoint, calendar_url
      @category_id, @category_label, @exact_empty_text = category_id, category_label, exact_empty_text
      @expected_total, @max_pages, @max_skew_seconds = expected_total, max_pages, max_skew_seconds
    end

    def call
      return invalid("invalid_capture_count") unless @captures.is_a?(Array) && (2..25).cover?(@captures.length) &&
        @max_pages.is_a?(Integer) && (2..25).cover?(@max_pages) && @captures.length <= @max_pages
      return invalid("invalid_evidence_options") unless [@category_id, @category_label, @exact_empty_text].all? do |value|
        value.is_a?(String) && !value.strip.empty?
      end && @max_skew_seconds.is_a?(Numeric) && @max_skew_seconds >= 0 &&
        (@expected_total.nil? || (@expected_total.is_a?(Integer) && @expected_total > 0))

      begin
        endpoint, calendar = URI.parse(@endpoint), URI.parse(@calendar_url)
        unless [endpoint, calendar].all? { |url| url.is_a?(URI::HTTPS) && url.host && !url.userinfo && !url.fragment } &&
          endpoint.host == calendar.host && endpoint.port == calendar.port && !endpoint.query
          return invalid("invalid_endpoint_or_calendar")
        end
      rescue URI::InvalidURIError
        return invalid("invalid_endpoint_or_calendar")
      end

      errors, timestamps, bodies, urls, signatures, templates, maximums = [], [], [], [], [], [], []
      first_fields = nil
      total = 0
      @captures.each_with_index do |capture, index|
        unless capture.is_a?(Hash) && capture["request"].is_a?(Hash) && capture["response"].is_a?(Hash)
          errors << "invalid_receipt:#{index}"
          next
        end
        request, response = capture.values_at("request", "response")
        fields = request["fields"]
        unless fields.is_a?(Hash) && fields.keys.sort == %w[action current_page filters[categ] number_items_per_page reference_id].sort &&
          request["method"] == "POST" && request["encoding"] == "multipart/form-data" && request["endpoint"] == @endpoint &&
          fields["reference_id"].is_a?(String) && !fields["reference_id"].empty? &&
          fields["filters[categ]"] == @category_id && fields["action"] == "null" &&
          fields["current_page"].to_s == (index + 1).to_s &&
          fields["number_items_per_page"].to_s.match?(/\A[1-9]\d*\z/) && fields["number_items_per_page"].to_i <= 100
          errors << "invalid_or_changed_request:#{index}"
          next
        end
        immutable = fields.reject { |key, _| key == "current_page" }
        first_fields ||= immutable
        errors << "filters_or_page_size_changed:#{index}" unless immutable == first_fields
        size = fields["number_items_per_page"].to_i

        begin
          timestamps << Time.iso8601(capture.fetch("captured_at"))
        rescue ArgumentError, TypeError, KeyError
          errors << "invalid_capture_time:#{index}"
        end
        unless response["http_status"] == 200 && response["content_type"].to_s.downcase.include?("application/json") &&
          response["body"].is_a?(String)
          errors << "untrusted_ajax_response:#{index}"
          next
        end
        bodies << Digest::SHA256.hexdigest(response["body"])
        begin
          payload = JSON.parse(response["body"])
        rescue JSON::ParserError
          errors << "invalid_json:#{index}"
          next
        end
        unless payload.is_a?(Hash) && payload["current_page"] == index + 1 && payload["count"].is_a?(Integer) &&
          payload["count"].between?(0, size) && payload["html"].is_a?(String) && payload["url"].is_a?(String) &&
          payload["max"].is_a?(Integer) && payload["max"] >= 0
          errors << "invalid_page_metadata:#{index}"
          next
        end
        maximums << payload["max"] # Observed but *never* interpreted as a page count/total.
        templates << payload["url"]
        unless valid_url_template?(payload["url"], index + 1, size, calendar)
          errors << "lost_filter_or_bad_url_template:#{index}"
        end
        fragment = Nokogiri::HTML.fragment(payload["html"])
        cards = fragment.css("a.cards__item")
        errors << "card_count_mismatch:#{index}" unless payload["count"] == cards.length &&
          fragment.css(".cards__item").length == cards.length
        cards.each do |card|
          href = card["href"]
          begin
            uri = URI.parse(href.to_s)
            unless uri.is_a?(URI::HTTPS) && uri.host == calendar.host && uri.port == calendar.port &&
              uri.path.start_with?("#{calendar.path.chomp('/')}/") && !uri.userinfo
              errors << "invalid_event_url:#{index}"
            end
          rescue URI::InvalidURIError
            errors << "invalid_event_url:#{index}"
          end
          urls << href
          errors << "category_mismatch:#{index}" unless card.at_css(".categ-top")&.text&.strip == @category_label
        end
        total += cards.length
        signatures << Digest::SHA256.hexdigest(payload["html"]) if cards.any?
        empty_marker = fragment.css("p").any? { |p| p.text.strip == @exact_empty_text }
        if index == @captures.length - 1
          errors << "missing_exact_empty_terminal:#{index}" unless cards.empty? && payload["count"] == 0 && empty_marker &&
            fragment.text.strip == @exact_empty_text
        elsif cards.empty? || empty_marker
          errors << "empty_or_terminal_before_last:#{index}"
        end
      end
      errors << "changed_response_url_template" unless templates.size == @captures.length && templates.uniq.size == 1
      errors << "inconsistent_max_metadata" unless maximums.size == @captures.length && maximums.uniq.size == 1
      errors << "repeated_nonterminal_html" if signatures.each_cons(2).any? { |a, b| a == b }
      errors << "capture_freshness_skew" if timestamps.any? && timestamps.max - timestamps.min > @max_skew_seconds
      errors << "expected_total_mismatch" if @expected_total && total != @expected_total
      errors << "no_event_discovery" if total.zero?
      digest = Digest::SHA256.hexdigest(JSON.generate(@captures.map.with_index do |receipt, i|
        [i + 1, receipt.is_a?(Hash) ? receipt.dig("request", "fields") : nil, bodies[i],
         receipt.is_a?(Hash) ? receipt["captured_at"] : nil]
      end))
      Result.new(status: errors.empty? ? "terminal_candidate" : "inconclusive", errors: errors.uniq,
                 terminal_page: @captures.length, card_occurrences: total, unique_event_urls: urls.compact.uniq.length,
                 digest: digest)
    end

    private

    def valid_url_template?(template, number, size, calendar)
      return false unless template.include?("{page_number}") && template.scan("{page_number}").length == 1
      uri = URI.parse(template.sub("{page_number}", number.to_s))
      return false unless uri.is_a?(URI::HTTPS) && uri.host == calendar.host && uri.port == calendar.port &&
        uri.path == calendar.path && !uri.userinfo && !uri.fragment
      params = URI.decode_www_form(uri.query.to_s)
      { "page" => number.to_s, "number_items" => size.to_s, "categ" => @category_id }.all? do |key, value|
        params.select { |k, _| k == key }.map(&:last) == [value]
      end
    rescue URI::InvalidURIError, ArgumentError
      false
    end

    def invalid(reason)
      Result.new(status: "inconclusive", errors: [reason], terminal_page: nil,
                 card_occurrences: 0, unique_event_urls: 0, digest: nil)
    end
  end
end
