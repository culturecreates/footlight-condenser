# frozen_string_literal: true

require "json"

module ResourceLists
  # Read-only assessment of one Signé Laval /api/events JSON response.
  # The API can return fewer items than per_page even before the last page;
  # therefore sparse intermediate pages are warnings, not terminal signals.
  class SigneLavalPageEvidence
    Result = Struct.new(:status, :errors, :warnings, :page, :count, :per_page,
      :total, :last_page, :is_last, :item_ids, keyword_init: true) do
      def valid_page? = status == "page_observed"
    end

    def self.call(body:, requested_page:, requested_per_page:)
      new(body:, requested_page:, requested_per_page:).call
    end

    def initialize(body:, requested_page:, requested_per_page:)
      @body, @requested_page, @requested_per_page = body, requested_page, requested_per_page
    end

    def call
      return failure("invalid_request") unless positive_integer?(@requested_page) && positive_integer?(@requested_per_page)
      return failure("missing_body") unless @body.is_a?(String) && !@body.empty?
      payload = JSON.parse(@body)
      return failure("invalid_envelope") unless payload.is_a?(Hash) && payload["items"].is_a?(Array) &&
        payload["pagination"].is_a?(Hash)
      items, meta = payload.values_at("items", "pagination")
      required = %w[page per_page count total last_page]
      return failure("invalid_pagination_metadata") unless required.all? { |key| meta[key].is_a?(Integer) } &&
        (meta["is_last"] == true || meta["is_last"] == false)

      page, size, count, total, last, is_last = meta.values_at("page", "per_page", "count", "total", "last_page", "is_last")
      return failure("invalid_pagination_metadata") unless positive_integer?(page) && positive_integer?(size) &&
        count.between?(0, size) && total >= 0 && positive_integer?(last) && (is_last == true || is_last == false)
      errors = []
      errors << "requested_page_mismatch" unless page == @requested_page
      errors << "requested_page_size_mismatch" unless size == @requested_per_page
      errors << "count_items_mismatch" unless count == items.length
      errors << "total_smaller_than_count" if total < count
      errors << "page_beyond_advertised_last" if page > last
      errors << "incorrect_last_page" if total.positive? && last != (total + size - 1) / size
      errors << "incorrect_is_last" unless is_last == (page == last)
      errors << "empty_calendar_unverified" if total.zero?
      ids = items.map { |item| item.is_a?(Hash) ? item["id"] : nil }
      errors << "missing_item_id" unless ids.all? { |id| id.is_a?(String) && !id.empty? }
      errors << "duplicate_item_id" unless ids.uniq.size == ids.size
      warnings = []
      warnings << "sparse_nonterminal_page" if count < size && !is_last
      Result.new(status: errors.empty? ? "page_observed" : "inconclusive", errors:, warnings:,
        page:, count:, per_page: size, total:, last_page: last, is_last:, item_ids: ids)
    rescue JSON::ParserError
      failure("invalid_json")
    end

    private

    def positive_integer?(value) = value.is_a?(Integer) && value.positive?

    def failure(code)
      Result.new(status: "inconclusive", errors: [code], warnings: [], page: nil,
        count: nil, per_page: nil, total: nil, last_page: nil, is_last: nil, item_ids: [])
    end
  end
end
