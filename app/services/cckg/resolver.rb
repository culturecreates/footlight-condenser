# frozen_string_literal: true

require_dependency 'cckg/place_resolver'
require_dependency 'cckg/selection_reason'

module CcKg
  class Resolver
    def self.call(query:, type:, context:, webpage:)
      new(query: query, type: type, context: context, webpage: webpage).search_cckg
    end

    def self.fetch_hits(query:, type:, context:, webpage:, use_structured_query:)
      new(query: query, type: type, context: context, webpage: webpage)
        .fetch_cckg_hits(query, type, webpage, use_structured_query)
    end

    def initialize(query:, type:, context:, webpage:)
      @query = query
      @type = type
      @context = context || {}
      @webpage = webpage
    end

    def search_cckg # returns a HASH
      return { data: [] } if @query.length <= 3

      clean = clean_query?(@query)
      province = @context[:province]
      locality = @context[:locality]

      use_structured_query = false
      Rails.logger.debug { "[CCKG] province=#{province.inspect} structured=#{use_structured_query}" }

      cckg_log(
        "INPUT",
        query: @query,
        class: @type,
        province: province.presence || "none",
        clean: clean,
        structured: use_structured_query
      )

      begin
        hits = fetch_cckg_hits(@query, @type, @webpage, use_structured_query)
      rescue StandardError => e
        cckg_log("ERROR", step: "fetch", class: e.class, message: e.message)
        return {
          error: "No server running at #{artsdata_recon_url}",
          method: 'search_cckg',
          message: "#{e.inspect}"
        }
      end

      cckg_log(
        "HITS",
        total: hits.size
      )

      if @type == "Place"
        best, reason = CcKg::PlaceResolver.call(
          hits: hits,
          query: @query,
          province: province,
          locality: locality
        )
        result = best ? [[best["name"], "http://kg.artsdata.ca/resource/#{best['id']}"]] : []
        selected_count = result.size
      else
        best_hits = select_cckg_hits(hits, @query, @type, @webpage, clean)
        filtered_hits = filter_cckg_hits(best_hits, @query, clean)

        # 🔥 Critical fallback (prevents silent data loss)
        if filtered_hits.empty? && best_hits.present?
          Rails.logger.warn("[CCKG][FALLBACK] filter removed all hits → using best_hits")
          filtered_hits = best_hits
        end

        result = map_cckg_results(filtered_hits)
        reason = CcKg::SelectionReason.for(
          query: @query,
          selected_hits: filtered_hits,
          province: province
        )
        selected_count = filtered_hits.size
      end

      cckg_log(
        "SELECT",
        reason: reason || "none",
        selected: selected_count,
        result: result.size
      )

      { data: result }
    end

    def fetch_cckg_hits(str, rdfs_class, webpage, use_structured_query)
      return fetch_structured_cckg_hits(str, extract_province(webpage)) if use_structured_query

      fetch_basic_cckg_hits(str, cckg_recon_type_for(rdfs_class))
    end

    def fetch_basic_cckg_hits(str, recon_type)
      escaped_query = cckg_escaped_query(str)
      response = HTTParty.get("#{artsdata_recon_url}?query=#{escaped_query}&type=#{recon_type}")

      unless response.code == 200
        raise StandardError, "CCKG recon request failed with status #{response.code}"
      end

      parsed = normalize_cckg_response(response)
      parsed["result"] || parsed.dig("q0", "result") || []
    end

    def fetch_structured_cckg_hits(str, province)
      payload = {
        q0: {
          query: str,
          type: "schema:Place",
          properties: [{ pid: "schema:address/schema:addressRegion", v: province }]
        }
      }

      response = HTTParty.get("#{artsdata_recon_url}?queries=#{CGI.escape(payload.to_json)}")
      cckg_log("REQUEST", mode: "structured")
      parsed = normalize_cckg_response(response)
      parsed.dig("q0", "result") || []
    end

    def select_cckg_hits(hits, str, rdfs_class, webpage, clean)
      province = extract_province(webpage)
      missing_province_context = cckg_missing_province_context?(webpage, province)

      if hits.size <= 1
        hits
      elsif clean && !(rdfs_class == "Place" && missing_province_context)
        best = select_best_hit(hits)
        best ? [best] : []
      else
        hits
      end
    end

    def filter_cckg_hits(hits, str, clean)
      normalized_query = normalize_string(CGI.unescapeHTML(str))
      return filter_noisy_hits(hits, normalized_query) unless clean

      hits.select do |h|
        next true if h["match"] == true

        hit_name = normalize_string(h["name"])
        normalized_query.include?(hit_name) || hit_name.include?(normalized_query)
      end
    end

    def filter_noisy_hits(hits, normalized_query)
      noisy_hits = hits.select do |h|
        raw_name = h["name"].to_s
        name = normalize_string(raw_name)
        trailing_segment = normalize_string(raw_name.split('-').last.to_s)

        (name.length >= 8 && normalized_query.include?(name)) ||
          (trailing_segment.length >= 8 && normalized_query.include?(trailing_segment))
      end

      noisy_hits.reject do |candidate|
        candidate_name = normalize_string(candidate["name"])
        noisy_hits.any? do |other|
          other != candidate &&
            normalize_string(other["name"]).include?(candidate_name) &&
            normalize_string(other["name"]).length > candidate_name.length
        end
      end
    end

    def map_cckg_results(hits)
      result = Array(hits).map do |h|
        [h["name"], "http://kg.artsdata.ca/resource/#{h['id']}"]
      end

      result.uniq! { |r| r[1] }
      result
    end

    def normalize_cckg_response(response)
      return response if response.is_a?(Hash)

      if response.respond_to?(:parsed_response)
        parsed = response.parsed_response
        return parsed if parsed.is_a?(Hash)
        return JSON.parse(parsed) if parsed.is_a?(String)
      end

      if response.respond_to?(:body)
        JSON.parse(response.body)
      else
        {}
      end
    rescue StandardError
      {}
    end

    def cckg_escaped_query(str)
      CGI.escape(CGI.unescapeHTML(str))
         .gsub('+', '%20')
         .gsub('%3A', ':')
    end

    private

    def clean_query?(str)
      return false if str.blank?

      str.length < 60 &&
        str !~ /\b(and|et)\b/i &&
        str !~ /,|&/
    end

    def cckg_log(step, **data)
      payload = data.compact.map { |k, v| "#{k}=#{cckg_log_value(v)}" }.join(" ")
      Rails.logger.debug { "[CCKG][#{step}] #{payload}".strip }
    end

    def cckg_log_value(value)
      str = value.to_s.gsub(/\s+/, ' ').strip
      str = "#{str[0, 120]}..." if str.length > 120
      str.include?(' ') ? "\"#{str}\"" : str
    end

    def normalize_string(s)
      s.to_s
       .downcase
       .gsub('&', ' and ')
       .gsub(/[^a-z0-9\s]/, ' ')
       .squeeze(' ')
       .strip
    end

    def extract_province(webpage)
      @context.key?(:province) ? @context[:province] : webpage&.website&.province
    end

    def cckg_recon_type_for(rdfs_class)
      rdfs_class == "EventType" ? "ado:EventType" : rdfs_class
    end

    def cckg_missing_province_context?(webpage, province)
      province.blank? && webpage&.website&.respond_to?(:province)
    end

    def select_best_hit(hits)
      return nil if hits.blank?

      auto = hits.select { |h| h["match"] == true }
      return auto.first if auto.size == 1

      hits.max_by { |h| h["score"].to_f }
    end

    def artsdata_recon_url
      if Rails.env.test?
        "http://localhost:#{ARTSDATA_API_PORT}/recon"
      elsif Rails.env.development?
        "http://localhost:#{ARTSDATA_API_PORT}/recon"
      else
        'http://api.artsdata.ca/recon'
      end
    end
  end
end