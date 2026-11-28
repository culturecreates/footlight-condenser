# frozen_string_literal: true

require "uri"

module ResourceLists
  # Read-only observation of the semantic Next *anchor*, not event extraction.
  # A missing or mismatched Next is never proof that a ResourceList is complete.
  class LabeledNextEvidence
    NEXT_LABEL = /\b(?:prochains?\s+evenements?|evenements?\s+suivants?|next(?:\s+(?:events?|page))?|suivant(?:e|es|s)?(?:\s+evenements?)?)\b/i
    Result = Struct.new(:status, :labeled_next_url, :numbered_forward_link_seen,
      :invalid_labeled_targets, :labeled_link_count, keyword_init: true)

    def self.call(anchors:, pagination:, page:, base_url:)
      raise ArgumentError, "Expected nonnegative page" unless page.is_a?(Integer) && page >= 0
      raise ArgumentError, "Expected anchors array" unless anchors.is_a?(Array)

      forward = false
      valid_labeled = []
      invalid_labeled = []
      labeled_count = 0
      anchors.each do |anchor|
        next unless anchor.is_a?(Hash)
        explicit_next = next_label?(anchor)
        raw_href = anchor[:href].to_s
        if raw_href.empty?
          if explicit_next
            labeled_count += 1
            invalid_labeled << "(missing href)"
          end
          next
        end
        begin
          absolute = URI.join(base_url, raw_href)
          # No fragment navigation or cross-origin/changed-filter targets.
          valid_forward = !absolute.fragment && pagination.matches_page?(absolute.to_s, page: page + 1)
          forward ||= valid_forward
          # A bare "More" is ambiguous (it may reveal details, not pages).
          # Recognize it only when its target is the verified next numbered page.
          labeled = explicit_next || (valid_forward && more_label?(anchor))
          labeled_count += 1 if labeled
          if labeled
            valid_forward ? valid_labeled << absolute.to_s : invalid_labeled << raw_href
          end
        rescue ArgumentError, URI::InvalidURIError
          if explicit_next
            labeled_count += 1
            invalid_labeled << raw_href
          end
        end
      end
      valid_labeled.uniq!
      status = if invalid_labeled.any? || valid_labeled.length > 1
        "inconclusive_labeled_target_conflict"
      elsif valid_labeled.one?
        "labeled_forward_observed"
      elsif forward
        "numbered_forward_only"
      else
        "no_forward_observed"
      end
      Result.new(status:, labeled_next_url: status == "labeled_forward_observed" ? valid_labeled.first : nil,
        numbered_forward_link_seen: forward, invalid_labeled_targets: invalid_labeled.uniq,
        labeled_link_count: labeled_count)
    end

    def self.next_label?(anchor)
      rel = anchor[:rel].to_s.split(/\s+/)
      return true if rel.any? { |r| r.casecmp?("next") }

      [anchor[:text], anchor[:aria_label], anchor[:title]].any? do |part|
        part.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").match?(NEXT_LABEL)
      end
    end
    private_class_method :next_label?

    # Unlike explicit "Next", "More" is only navigation evidence when the
    # already-validated target is exactly page+1 with unchanged filters.
    def self.more_label?(anchor)
      anchor[:text].to_s.strip.casecmp?("more")
    end
    private_class_method :more_label?
  end
end
