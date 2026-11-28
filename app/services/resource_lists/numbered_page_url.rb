# frozen_string_literal: true

require "uri"
require_relative "numbered_page_path"
require_relative "numbered_page_query"

module ResourceLists
  # Select a verified numeric page-address grammar. No speculative page URLs.
  module NumberedPageURL
    def self.build(start_url:, parameter: nil)
      if parameter == NumberedPagePath::PARAMETER || (parameter.nil? && NumberedPagePath.supports?(start_url))
        parsed = URI.parse(start_url.to_s)
        raise ArgumentError, "Ambiguous path and query pagination" if
          URI.decode_www_form(parsed.query.to_s).any? { |key, _| NumberedPageQuery::PARAMETERS.include?(key) }
        return NumberedPagePath.new(start_url:)
      end
      NumberedPageQuery.new(start_url:, parameter:)
    end
  end
end
