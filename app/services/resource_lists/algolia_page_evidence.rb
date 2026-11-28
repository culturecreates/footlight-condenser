# frozen_string_literal: true

module ResourceLists
  # Offline evidence from a specifically identified Algolia search response.
  # Caller must verify HTTP/JSON, query identity, filters, and response slot.
  # Algolia nbPages may describe a capped accessible result window.
  class AlgoliaPageEvidence
    Result = Struct.new(:status, :errors, :next_api_page, :last_accessible_api_page,
      :reported_hits, :hits_per_page, :limit_suspected, keyword_init: true)

    def self.call(response:, requested_api_page:, expected_index:, request_index:, response_slot_verified:, http_status:)
      errors = []
      errors << "http_not_successful" unless http_status == 200
      errors << "unverified_response_slot" unless response_slot_verified == true
      errors << "index_mismatch" unless request_index.is_a?(String) && !request_index.empty? && request_index == expected_index
      return inconclusive(errors) unless errors.empty?
      return inconclusive(["invalid_response"]) unless response.is_a?(Hash)

      page, pages, size, total, hits = response.values_at("page", "nbPages", "hitsPerPage", "nbHits", "hits")
      errors << "invalid_page" unless page.is_a?(Integer) && page >= 0 && requested_api_page == page
      errors << "invalid_nb_pages" unless pages.is_a?(Integer) && pages >= 0
      errors << "invalid_hits_per_page" unless size.is_a?(Integer) && size.positive?
      errors << "invalid_nb_hits" unless total.is_a?(Integer) && total >= 0
      errors << "invalid_hits" unless hits.is_a?(Array) && size.is_a?(Integer) && hits.size <= size
      return inconclusive(errors) unless errors.empty?

      return inconclusive(["inconsistent_empty_result"]) if pages.zero? && (page != 0 || total != 0 || !hits.empty?)
      return inconclusive(["page_outside_reported_range"]) if pages.positive? && page >= pages
      return inconclusive(["nonempty_hits_with_zero_total"]) if total.zero? && !hits.empty?
      return inconclusive(["inconsistent_pagination_count"]) if pages.positive? && pages > (total.to_f / size).ceil

      # A configured paginationLimitedTo cap can hide pages despite nbHits.
      capped = pages.positive? && total > pages * size
      status = if pages.zero?
        "no_hits_candidate"
      elsif page + 1 == pages
        "last_accessible_page_candidate"
      else
        "forward_observed_by_metadata"
      end
      Result.new(status:, errors: [], next_api_page: status == "forward_observed_by_metadata" ? page + 1 : nil,
        last_accessible_api_page: pages.positive? ? pages - 1 : nil, reported_hits: total,
        hits_per_page: size, limit_suspected: capped)
    end

    def self.inconclusive(errors)
      Result.new(status: "inconclusive", errors:, next_api_page: nil,
        last_accessible_api_page: nil, reported_hits: nil, hits_per_page: nil, limit_suspected: nil)
    end
    private_class_method :inconclusive
  end
end
