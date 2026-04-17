# frozen_string_literal: true

require_dependency 'cckg/selection_reason'

module CcKg
  class PlaceResolver
    def self.call(hits:, query:, province:, locality:)
      new(hits, query, province, locality).resolve
    end

    def initialize(hits, query, province, locality)
      @hits = hits
      @query = query
      @province = province
      @locality = locality
    end

    def resolve
      if @hits.blank?
        log_cckg("FINAL", "reason=none")
        return [nil, SelectionReason.for(query: @query, selected_hits: [], province: @province, resolved_by: :none)]
      end

      log_cckg("RESOLVE", "query='#{@query}' hits=#{@hits.size}")
      @exact_matches = []
      @candidates = @hits

      strategies.each do |strategy|
        result = send(strategy)
        return result if result
      end

      fallback_resolution
    end

    private

    def strategies
      [
        :single_hit,
        :exact_match,
        :province_match,
        :locality_match
      ]
    end

    def single_hit
      return nil unless @hits.size == 1

      log_cckg("FINAL", "reason=single name='#{@hits.first['name']}'")
      [@hits.first, SelectionReason.for(query: @query, selected_hits: [@hits.first], province: @province, resolved_by: :single)]
    end

    def exact_match
      normalized_query = normalize_string(@query)
      @exact_matches = @hits.select { |h| normalize_string(h["name"]) == normalized_query }
      log_cckg("EXACT", "matches=#{@exact_matches.size}")

      if @exact_matches.size == 1
        log_cckg("FINAL", "reason=exact name='#{@exact_matches.first['name']}'")
        return [@exact_matches.first, SelectionReason.for(query: @query, selected_hits: [@exact_matches.first], province: @province, resolved_by: :exact)]
      end

      @candidates = @exact_matches.presence || @hits
      nil
    end

    def province_match
      return nil unless @exact_matches.size > 1 && @province.present?

      province_matches = @exact_matches.select { |h| cckg_province_match?(h, @province) }

      log_cckg("PROVINCE", "province=#{@province} matches=#{province_matches.size}")

      if province_matches.size == 1
        log_cckg("FINAL", "reason=province name='#{province_matches.first['name']}'")
        return [province_matches.first, SelectionReason.for(query: @query, selected_hits: [province_matches.first], province: @province, resolved_by: :province)]
      end

      @candidates = province_matches if province_matches.any?
      nil
    end

    def locality_match
      return nil unless @candidates.size > 1 && @locality.present?

      locality_regex = /\b#{Regexp.escape(@locality.to_s)}\b/i
      locality_matches = @candidates.select do |h|
        [
          h["description"],
          h["addressLocality"],
          h.dig("address", "addressLocality")
        ].compact.any? { |v| v.to_s.match?(locality_regex) }
      end
      log_cckg("LOCALITY", "locality=#{@locality} matches=#{locality_matches.size}")

      if locality_matches.size == 1
        log_cckg("FINAL", "reason=locality name='#{locality_matches.first['name']}'")
        return [locality_matches.first, SelectionReason.for(query: @query, selected_hits: [locality_matches.first], province: @province, resolved_by: :locality)]
      end

      @candidates = locality_matches if locality_matches.any?
      nil
    end

    def fallback_resolution
      best = (@candidates.presence || @hits).max_by { |h| h["score"].to_f }
      unless best.present?
        return [nil, SelectionReason.for(query: @query, selected_hits: [], province: @province, resolved_by: :none)].tap do
          log_cckg("FINAL", "reason=none")
        end
      end

      log_cckg("FINAL", "reason=score name='#{best['name']}' score=#{best['score']}")
      reason = SelectionReason.for(
        query: @query,
        selected_hits: [best.merge("match" => false)],
        province: @province,
        resolved_by: :fallback,
        exact_pool_size: @exact_matches.size
      )
      [best, reason]
    end

    def normalize_string(s)
      s.to_s
       .downcase
       .gsub('&', ' and ')
       .gsub(/[^a-z0-9\s]/, ' ')
       .squeeze(' ')
       .strip
    end

    def cckg_province_match?(hit, province)
      return false if province.blank?

      hit_province =
        hit["addressRegion"] ||
        hit["province"] ||
        hit.dig("address", "addressRegion")

      return true if hit_province.to_s.casecmp?(province.to_s)

      description = hit["description"].to_s
      description.match?(/\b#{Regexp.escape(province.to_s)}\b/i)
    end

    def log_cckg(stage, msg)
      Rails.logger.debug { "[CCKG][#{stage}] #{msg}" }
    end
  end
end

