# frozen_string_literal: true

module ResourceLists
  # Read-only classification of selected ResourceList RDF identifiers. A
  # footlight: CURIE is interchangeable with the corresponding absolute KG
  # URI *only after expansion*. A slug identifier is not equivalent to a
  # hashed QA-copy Webpage identifier merely because their labels resemble.
  class MeridianCacheIdentityDiagnostics
    ROOT = "http://kg.footlight.io/resource/"
    PREFIX = "footlight:"

    def self.expand(uri)
      value = uri.to_s
      return "#{ROOT}#{value.delete_prefix(PREFIX)}" if value.start_with?(PREFIX)
      value
    end

    def self.namespace(uri, original_seedurl:, qa_seedurl:)
      expanded = expand(uri)
      return "qa" if expanded.start_with?("#{ROOT}#{qa_seedurl}_")
      return "original" if expanded.start_with?("#{ROOT}#{original_seedurl}_")
      "other"
    end

    def self.call(entries:, events_by_url:, original_seedurl:, qa_seedurl:)
      counts = Hash.new(0)
      mismatches = []
      entries.each do |row|
        cached = expand(row.fetch(:rdf_uri))
        ns = namespace(row.fetch(:rdf_uri), original_seedurl: original_seedurl, qa_seedurl: qa_seedurl)
        existing = Array(events_by_url[row.fetch(:url)]).map { |value| expand(value) }.uniq
        kind = if existing.empty?
          "missing_webpage"
        elsif existing.include?(cached)
          row.fetch(:rdf_uri).to_s == cached ? "exact_identifier" : "expanded_identifier_matches"
        elsif ns == "original"
          "original_namespace_vs_qa_webpage"
        elsif ns == "qa"
          "qa_namespace_distinct_identity"
        else
          "unrecognized_namespace"
        end
        counts[kind] += 1
        mismatches << { rl_id: row.fetch(:rl_id), url: row.fetch(:url), position: row.fetch(:position),
          cached_uri: row.fetch(:rdf_uri), existing_uris: existing, namespace: ns, kind: kind } unless
          %w[exact_identifier expanded_identifier_matches].include?(kind)
      end

      conflicts = entries.group_by { |row| row.fetch(:url) }.filter_map do |url, rows|
        variants = rows.map { |row| expand(row.fetch(:rdf_uri)) }.uniq
        next unless variants.size > 1
        categories = variants.map { |uri| namespace(uri, original_seedurl: original_seedurl, qa_seedurl: qa_seedurl) }.uniq.sort
        { url: url, rdf_uris: variants, namespace_categories: categories,
          classification: categories == %w[original qa] ? "original_vs_qa_namespace" : "distinct_uris" }
      end
      { row_counts_by_kind: counts.sort.to_h, unresolved_rows: mismatches,
        conflicting_urls: conflicts, unique_unresolved_urls: mismatches.map { |row| row[:url] }.uniq.size,
        note: "Expanded CURIE equality is safe; original/QA namespace substitution and slug/hash equivalence are NOT inferred." }
    end
  end
end
