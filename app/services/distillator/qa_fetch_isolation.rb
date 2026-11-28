# frozen_string_literal: true

require "digest"

module Distillator
  # A copied QA website has independent cached fetches even though its Webpages
  # intentionally retain the original public URLs. Normal websites keep the
  # Wringer-compatible URL key and cache behavior unchanged.
  class QaFetchIsolation
    def self.website_id(website: nil, website_id: nil, log_context: {})
      context = log_context.respond_to?(:to_h) ? log_context.to_h.symbolize_keys : {}
      record = website if website.respond_to?(:test_copy_of_website_id)
      record ||= Website.find_by(id: website_id.presence || context[:website_id]) if website_id.present? || context[:website_id].present?
      record.id if record&.test_copy_of_website_id.present?
    end

    def self.cache_key(uri_key:, website_id:)
      return uri_key if website_id.blank?

      # Fixed length: uri_key is varchar(255), and URLs can already be long.
      "qa:#{website_id}:#{Digest::SHA256.hexdigest(uri_key)}"
    end
  end
end
