# frozen_string_literal: true

module ResourceLists
  # Operates on response facts supplied by a *verified* JSON schema observer.
  # Does not guess field names, inspect product records, or certify completeness.
  class OffsetJsonTerminalEvidence
    Result = Struct.new(:status, :errors, :next_offset, keyword_init: true)

    def self.call(offset:, page_size:, http_status:, content_type:, json_valid:, schema_verified:, record_count:,
      has_more: nil, reported_total: nil)
      errors = []
      errors << "invalid_offset" unless offset.is_a?(Integer) && offset >= 0
      errors << "invalid_page_size" unless page_size.is_a?(Integer) && page_size.positive?
      errors << "http_not_successful" unless http_status == 200
      errors << "not_json" unless content_type.to_s.match?(%r{\Aapplication/(?:[a-z0-9.-]+\+)?json\b}i) && json_valid == true
      errors << "unknown_response_schema" unless schema_verified == true
      errors << "invalid_record_count" unless record_count.is_a?(Integer) && record_count >= 0 &&
        page_size.is_a?(Integer) && page_size.positive? && record_count <= page_size
      errors << "invalid_has_more" unless [true, false, nil].include?(has_more)
      errors << "invalid_reported_total" unless reported_total.nil? || (reported_total.is_a?(Integer) && reported_total >= 0)
      return Result.new(status: "inconclusive", errors:, next_offset: nil) if errors.any?

      end_index = offset + record_count
      if has_more == true && (record_count.zero? || (!reported_total.nil? && end_index >= reported_total))
        errors << "contradictory_forward_metadata"
      elsif has_more == false && !reported_total.nil? && end_index < reported_total
        errors << "contradictory_terminal_metadata"
      end
      return Result.new(status: "inconclusive", errors:, next_offset: nil) if errors.any?

      status = if has_more == false
        "terminal_candidate_explicit"
      elsif has_more == true
        "forward_observed"
      elsif !reported_total.nil? && end_index >= reported_total
        "terminal_candidate_reported_total"
      elsif record_count == page_size
        "forward_candidate_full_batch"
      else
        "inconclusive_short_or_empty_batch"
      end
      next_index = %w[forward_observed forward_candidate_full_batch].include?(status) ? offset + page_size : nil
      Result.new(status:, errors: [], next_offset: next_index)
    end
  end
end
