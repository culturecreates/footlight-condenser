# frozen_string_literal: true

module Cckg
  class SelectionReason
    def self.for(query:, selected_hits:, province:, resolved_by: nil, exact_pool_size: nil)
      new(
        query: query,
        selected_hits: selected_hits,
        province: province,
        resolved_by: resolved_by,
        exact_pool_size: exact_pool_size
      ).call
    end

    def initialize(query:, selected_hits:, province:, resolved_by:, exact_pool_size:)
      @query = query
      @selected_hits = selected_hits
      @province = province
      @resolved_by = resolved_by
      @exact_pool_size = exact_pool_size
    end

    def call
      return mapped_reason if mapped_reason

      # Fallback only if resolver didn't provide a reason (should be rare)
      return "exact" if exact_match?
      return "province" if province_match_in_selected_hits?

      "fallback_score"
    end

    private

    attr_reader :query, :selected_hits, :province, :resolved_by, :exact_pool_size

    # === PRIMARY: trust resolver ===
    def mapped_reason
      case resolved_by
      when :single
        "single"
      when :exact
        "exact"
      when :province
        "province"
      when :locality
        "locality"
      when :none
        "none"
      when :fallback
        reason = base_reason

        # If there were exact candidates but we still fell back,
        # do NOT report "province" — this is a true fallback
        if exact_pool_size.to_i > 0 && reason == "province"
          "fallback_score"
        else
          reason
        end
      end
    end

    # === SECONDARY: heuristic fallback (safety net only) ===
    def base_reason
      return "exact" if exact_match?
      return "province" if province_match_in_selected_hits?

      "fallback_score"
    end

    def normalized_query
      @normalized_query ||= normalize(CGI.unescapeHTML(query.to_s))
    end

    def exact_match?
      selected_hits.any? do |hit|
        hit["match"] == true ||
          normalize(hit["name"]) == normalized_query
      end
    end

    def province_match_in_selected_hits?
      return false if province.blank?

      selected_hits.any? do |hit|
        hit_province =
          hit["addressRegion"] ||
          hit["province"] ||
          hit.dig("address", "addressRegion")

        hit_province.to_s.casecmp?(province.to_s) ||
          hit["description"].to_s.match?(/\b#{Regexp.escape(province.to_s)}\b/i)
      end
    end

    def normalize(str)
      str.to_s
         .downcase
         .gsub('&', ' and ')
         .gsub(/[^a-z0-9\s]/, ' ')
         .squeeze(' ')
         .strip
    end
  end
end