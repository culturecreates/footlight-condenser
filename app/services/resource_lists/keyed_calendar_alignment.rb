# frozen_string_literal: true

require "digest"
require "json"

module ResourceLists
  # Aligns *discovered* language-specific URLs by a site-provided key, before
  # any Webpage or RDF URI is created. Pure/read-only: no fetching or DB writes.
  # The caller is responsible for providing complete, validated page inventories.
  class KeyedCalendarAlignment
    Pair = Struct.new(:key, :urls, keyword_init: true)
    Result = Struct.new(:status, :languages, :pairs, :unmatched, :errors, :digest, keyword_init: true) do
      def complete?
        status == "complete"
      end

      def paired_urls_for(language)
        raise ArgumentError, "Incomplete/invalid keyed calendar alignment" unless complete?
        lang = language.to_s.downcase
        raise ArgumentError, "Unknown language: #{language}" unless languages.include?(lang)

        pairs.map { |pair| pair.urls.fetch(lang) }
      end
    end

    def self.call(streams:)
      new(streams: streams).call
    end

    def initialize(streams:)
      @streams = streams
    end

    def call
      raise ArgumentError, "streams must be a nonempty language => records hash" unless @streams.is_a?(Hash) && !@streams.empty?

      errors = []
      indexed = {}
      @streams.each do |language, records|
        lang = language.to_s.strip.downcase
        unless lang.match?(/\A[a-z]{2,3}(?:-[a-z0-9]+)*\z/)
          errors << "invalid_language: #{language.inspect}"
          next
        end
        if indexed.key?(lang)
          errors << "duplicate_language: #{lang}"
          next
        end
        unless records.is_a?(Array)
          errors << "invalid_records: #{lang}"
          next
        end
        by_key = {}
        by_url = {}
        records.each_with_index do |record, index|
          unless record.is_a?(Hash)
            errors << "invalid_record: #{lang}[#{index}]"
            next
          end
          key = (record[:key] || record["key"]).to_s.strip
          url = (record[:url] || record["url"]).to_s.strip
          if key.empty? || url.empty?
            errors << "missing_key_or_url: #{lang}[#{index}]"
            next
          end
          if by_key.key?(key) && by_key[key] != url
            errors << "duplicate_key: #{lang}:#{key}"
            next
          end
          if by_url.key?(url) && by_url[url] != key
            errors << "conflicting_keys_for_url: #{lang}:#{url}"
            next
          end
          # The exact same key/URL can appear on overlapping pagination pages.
          by_key[key] = url
          by_url[url] = key
        end
        indexed[lang] = by_key
      end

      languages = indexed.keys.sort
      pairs = indexed.values.flat_map(&:keys).uniq.sort.map do |key|
        Pair.new(key: key, urls: languages.each_with_object({}) { |lang, urls| urls[lang] = indexed.fetch(lang)[key] })
      end
      unmatched = pairs.select { |pair| pair.urls.values.any?(&:nil?) }
      digest = Digest::SHA256.hexdigest(JSON.generate(pairs.map { |pair| [pair.key, languages.map { |lang| pair.urls[lang] }] }))
      status = errors.any? ? "invalid" : unmatched.any? ? "incomplete" : "complete"
      Result.new(status: status, languages: languages, pairs: pairs, unmatched: unmatched, errors: errors, digest: digest)
    end
  end
end
