# frozen_string_literal: true

require "uri"

module ResourceLists
  # Read-only, one-click diagnostic for the isolated Danse Danse QA copy.
  # Fetches exactly the two configured first calendar pages, without writing
  # cache, Statements, Webpages or jobs. This does NOT prove pagination coverage.
  class DanseDanseKeyedPreview
    Invalid = Class.new(StandardError)
    MAX_HTML_BYTES = 5 * 1024 * 1024
    ROOT = DanseDanseKeyedQaRefresh::ROOT
    LANGUAGES = DanseDanseKeyedQaRefresh::LANGUAGES

    Result = Struct.new(:status, :rows, :errors, :counts, :digest, :unmatched_keys, :fetch_paths, keyword_init: true)

    def self.eligible?(website)
      website&.persisted? && website.seedurl == "dansedansetest-ca" &&
        website.test_copy_of_website&.seedurl == "dansedanse-ca" &&
        website.distillator_mode == "shadow" && !website.refresh_scheduled?
    end

    def self.call(website:)
      new(website: website).call
    end

    def initialize(website:)
      @website = website
    end

    def call
      raise Invalid, "Only the unscheduled Danse Danse QA copy may run this preview" unless self.class.eligible?(@website)

      streams, errors, counts, fetch_paths = {}, [], {}, {}
      resource_list_class = RdfsClass.find_by(name: "ResourceList")
      raise Invalid, "ResourceList class not found" unless resource_list_class

      LANGUAGES.each do |language, config|
        url = ROOT + config.fetch(:path)
        lists = @website.webpages.where(rdfs_class: resource_list_class, language: language, url: url)
        unless lists.count == 1
          errors << "#{language}: expected exactly one QA ResourceList at #{url}, found #{lists.count}"
          next
        end

        # Explicit internal fetch avoids shadow double-fetch and does not go
        # through FetchCacheStore; URL is fixed by the trusted site configuration.
        fetched = Distillator::FetchService.fetch_result(url: url, render_js: false, scrape_options: {}, mode: :internal)
        unless fetched[:status].to_s == "ok" && fetched[:http_code].to_i == 200 &&
            fetched[:body].is_a?(String) && fetched[:body].bytesize.between?(1, MAX_HTML_BYTES)
          errors << "#{language}: calendar fetch failed or returned invalid HTML (status=#{fetched[:status]}, http=#{fetched[:http_code]})"
          next
        end
        final_url = fetched[:final_url].presence || url
        unless URI.parse(final_url).host == URI.parse(url).host &&
            URI.parse(final_url).path.delete_suffix("/") == URI.parse(url).path.delete_suffix("/")
          errors << "#{language}: calendar redirected outside the configured language path"
          next
        end

        item_xpath = "//div[contains(@class,'section--listing-spectacles__container')]" \
          "//div[contains(concat(' ',normalize-space(@class),' '),' block--spectacle ')]" \
          "[.//div[contains(@class,'block--spectacle__title--info--category')]/span[normalize-space(.)='#{config.fetch(:category)}']]"
        extracted = KeyedCalendarExtractor.call(html: fetched[:body], base_url: url, item_xpath: item_xpath,
          url_xpath: "./a[1]/@href", key_xpath: "./a[1]/@href", key_mode: :url_last_segment)
        errors.concat(extracted.errors.map { |error| "#{language}: #{error}" })
        streams[language] = extracted.records
        counts[language] = extracted.records.size
        fetch_paths[language] = fetched[:fetch_path].to_s
      rescue URI::InvalidURIError => error
        errors << "#{language}: invalid redirect URL: #{error.message}"
      rescue StandardError => error
        Rails.logger.warn(event: "resource_list.keyed_preview_fetch_failed", website_id: @website.id,
          language: language, error_class: error.class.name)
        errors << "#{language}: preview failed (#{error.class.name})"
      end

      return result("blocked", [], errors, counts, nil, [], fetch_paths) if errors.any? || streams.keys.sort != LANGUAGES.keys.sort

      alignment = KeyedCalendarAlignment.call(streams: streams)
      errors.concat(alignment.errors)
      urls = alignment.pairs.flat_map { |pair| pair.urls.values.compact }.uniq
      existing = @website.webpages.event_pages.where(url: urls).pluck(:url, :language, :rdf_uri)
        .to_h { |url, language, rdf_uri| [url, { language: language, rdf_uri: rdf_uri }] }
      rows = alignment.pairs.map do |pair|
        present = pair.urls.filter_map do |language, url|
          next unless url
          page = existing[url]
          next unless page
          errors << "#{language}: Webpage language mismatch for #{url}" if page[:language] != language
          page[:rdf_uri]
        end
        rdf_uris = present.uniq
        condition = if pair.urls.values.any?(&:nil?)
          "missing_translation"
        elsif rdf_uris.size > 1
          "rdf_uri_conflict"
        elsif pair.urls.values.any? { |url| !existing.key?(url) }
          "new_or_missing_webpage"
        else
          "existing_pair"
        end
        { key: pair.key, en: pair.urls["en"], fr: pair.urls["fr"],
          rdf_uri: rdf_uris.one? ? rdf_uris.first : nil, condition: condition }
      end
      errors.concat(alignment.unmatched.map { |pair| "Unmatched translation key: #{pair.key}" })
      errors.concat(rows.select { |row| row[:condition] == "rdf_uri_conflict" }.map { |row| "RDF URI conflict: #{row[:key]}" })
      status = errors.empty? && rows.all? { |row| row[:condition] == "existing_pair" } ? "preview_only" : "needs_review"
      result(status, rows, errors, counts, alignment.digest, alignment.unmatched.map(&:key), fetch_paths)
    end

    private

    def result(status, rows, errors, counts, digest, unmatched, fetch_paths)
      Result.new(status: status, rows: rows, errors: errors, counts: counts, digest: digest,
        unmatched_keys: unmatched, fetch_paths: fetch_paths)
    end
  end
end
