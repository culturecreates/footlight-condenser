# frozen_string_literal: true

module ResourceLists
  # Read-only observation of a textual "Page X de Y", "Page X/Y" or "Page X of Y" label in saved HTML.
  # Matching text is not proof that the label belongs to the calendar pager;
  # an authenticated selector and full capture must verify it independently.
  class NumberedPageLabel
    Result = Struct.new(:status, :page, :last_page, :errors, keyword_init: true) do
      def observed? = status == "label_observed"
    end

    def self.call(text:, expected_page:)
      return inconclusive("invalid_expected_page") unless expected_page.is_a?(Integer) && expected_page.positive?
      return inconclusive("missing_text") unless text.is_a?(String)

      candidates = text.scan(/\bPage\s+(\d+)\s*(?:de\s+|of\s+|\/\s*)(\d+)\b/i).uniq
      return inconclusive("missing_page_label") if candidates.empty?
      return inconclusive("ambiguous_page_labels") unless candidates.one?

      page, last = candidates.first.map(&:to_i)
      return inconclusive("invalid_page_range") if page.zero? || last.zero? || page > last
      return inconclusive("requested_page_mismatch") unless page == expected_page

      Result.new(status: "label_observed", page:, last_page: last, errors: [])
    end

    def self.inconclusive(reason)
      Result.new(status: "inconclusive", page: nil, last_page: nil, errors: [reason])
    end
    private_class_method :inconclusive
  end
end
