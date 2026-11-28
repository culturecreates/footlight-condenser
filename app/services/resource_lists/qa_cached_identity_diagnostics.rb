# frozen_string_literal: true

module ResourceLists
  # Pure read-only classification of cached ResourceList URI identities against
  # existing QA Webpages. Does not infer pairing from URL order or rewrite RDF.
  class QaCachedIdentityDiagnostics
    def self.call(entries:, events_by_url:, qa_seedurl:, original_seedurl:)
      qa_prefix = "http://kg.footlight.io/resource/#{qa_seedurl}_"
      orig_prefix = "http://kg.footlight.io/resource/#{original_seedurl}_"
      issues = entries.filter_map do |row|
        existing = events_by_url.fetch(row.fetch(:url), []).map(&:last).uniq.sort
        next if existing.empty?
        cached = row.fetch(:rdf_uri)
        normalized = expand_footlight(cached)
        next if existing.include?(cached)

        reason = if existing.include?(normalized)
          "curie_representation_only"
        elsif normalized.start_with?(orig_prefix)
          "original_site_identity"
        elsif normalized.start_with?(qa_prefix) && existing.any? { |uri| uri.match?(%r{\A#{Regexp.escape(qa_prefix)}[0-9a-f]{24}\z}) } &&
            normalized.start_with?("#{qa_prefix}bilingual_")
          "qa_slug_vs_hashed_clone_identity"
        elsif normalized.start_with?(qa_prefix)
          "different_qa_identity"
        else
          "unknown_identity_namespace"
        end
        row.slice(:rl_id, :language, :position, :url, :rdf_uri).merge(
          normalized_cached_uri: normalized, existing_rdf_uris: existing, reason: reason
        )
      end
      {
        examined_entries: entries.size,
        issues: issues,
        category_counts: issues.group_by { |row| row.fetch(:reason) }.transform_values(&:size),
        by_resource_list: issues.group_by { |row| row.fetch(:rl_id) }
          .transform_values { |rows| rows.group_by { |r| r.fetch(:reason) }.transform_values(&:size) },
        note: "Compare normalized CURIE representations only. Identity mismatches are diagnostic, not a license to remint or import."
      }
    end

    def self.expand_footlight(value)
      text = value.to_s
      return text unless text.start_with?("footlight:")
      "http://kg.footlight.io/resource/#{text.delete_prefix('footlight:')}"
    end
    private_class_method :expand_footlight
  end
end
