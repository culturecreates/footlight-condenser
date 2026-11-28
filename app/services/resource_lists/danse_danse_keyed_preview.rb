# frozen_string_literal: true

require "uri"

module ResourceLists
  # Read-only, one-click diagnostic for the isolated Danse Danse QA copy.
  # Fetches all explicitly configured Danse Danse calendar ResourceLists in both
  # languages without writing cache, Statements, Webpages or jobs. Contiguous
  # configured pages still do NOT prove the live site's terminal page.
  class DanseDanseKeyedPreview
    Invalid = Class.new(StandardError)
    MAX_HTML_BYTES = 5 * 1024 * 1024
    MAX_TOTAL_HTML_BYTES = 25 * MAX_HTML_BYTES
    ROOT = DanseDanseKeyedQaRefresh::ROOT
    LANGUAGES = DanseDanseKeyedQaRefresh::LANGUAGES

    Result = Struct.new(:status, :rows, :errors, :counts, :digest, :unmatched_keys, :fetch_paths,
      :page_counts, :page_details, keyword_init: true)

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

      streams, errors, counts, fetch_paths, page_counts, page_details = {}, [], {}, {}, {}, {}
      resource_list_class = RdfsClass.find_by(name: "ResourceList")
      raise Invalid, "ResourceList class not found" unless resource_list_class

      # Snapshot configured URLs first. Do not discover or create new ResourceList
      # rows during this read-only diagnostic.
      configured_lists = @website.webpages.where(rdfs_class: resource_list_class).to_a

      LANGUAGES.each do |language, config|
        configured = ConfiguredCalendarPages.call(
          webpages: configured_lists.select { |page| page.language == language },
          root: ROOT, path: config.fetch(:path)
        )
        page_details[language] = []
        page_counts[language] = configured.pages.size
        unless configured.valid?
          errors.concat(configured.errors.map { |error| "#{language}: #{error}" })
          next
        end

        item_xpath = "//div[contains(@class,'section--listing-spectacles__container')]" \
          "//div[contains(concat(' ',normalize-space(@class),' '),' block--spectacle ')]" \
          "[.//div[contains(@class,'block--spectacle__title--info--category')]/span[normalize-space(.)='#{config.fetch(:category)}']]"
        records, fetch_paths_for_language, total_bytes = [], [], 0
        configured.pages.each do |page|
          # Fixed configured same-origin URL; no page enumeration or new URLs guessed.
          fetched = Distillator::FetchService.fetch_result(url: page.url, render_js: false,
            scrape_options: {}, mode: :internal)
          unless fetched[:status].to_s == "ok" && fetched[:http_code].to_i == 200 &&
              fetched[:body].is_a?(String) && fetched[:body].bytesize.between?(1, MAX_HTML_BYTES)
            errors << "#{language} page #{page.number}: fetch failed or returned invalid HTML (status=#{fetched[:status]}, http=#{fetched[:http_code]})"
            break
          end
          total_bytes += fetched[:body].bytesize
          if total_bytes > MAX_TOTAL_HTML_BYTES
            errors << "#{language}: maximum total calendar HTML size exceeded"
            break
          end
          final_url = fetched[:final_url].presence || page.url
          unless equivalent_calendar_url?(final_url, page.url)
            errors << "#{language} page #{page.number}: redirected outside the configured page URL"
            break
          end
          extracted = KeyedCalendarExtractor.call(html: fetched[:body], base_url: page.url,
            item_xpath: item_xpath, url_xpath: "./a[1]/@href", key_xpath: "./a[1]/@href",
            key_mode: :url_last_segment)
          unless extracted.valid?
            errors.concat(extracted.errors.map { |error| "#{language} page #{page.number}: #{error}" })
            break
          end
          records.concat(extracted.records)
          fetch_paths_for_language << fetched[:fetch_path].to_s
          page_details[language] << { number: page.number, url: page.url, count: extracted.records.size }
        rescue StandardError => error
          Rails.logger.warn(event: "resource_list.keyed_preview_fetch_failed", website_id: @website.id,
            language: language, page: page.number, error_class: error.class.name)
          errors << "#{language} page #{page.number}: preview failed (#{error.class.name})"
          break
        end
        next if errors.any?

        streams[language] = records
        counts[language] = records.map { |record| record.fetch(:key) }.uniq.size
        fetch_paths[language] = fetch_paths_for_language.uniq.join(",")
      end

      return result("blocked", [], errors, counts, nil, [], fetch_paths, page_counts, page_details) if errors.any? ||
        streams.keys.sort != LANGUAGES.keys.sort

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
      result(status, rows, errors, counts, alignment.digest, alignment.unmatched.map(&:key), fetch_paths, page_counts, page_details)
    end

    private

    def equivalent_calendar_url?(actual, expected)
      observed, configured = URI.parse(actual), URI.parse(expected)
      observed.scheme == "https" && configured.scheme == "https" &&
        observed.host == configured.host && observed.port == configured.port &&
        observed.userinfo.nil? && configured.userinfo.nil? &&
        observed.path.sub(%r{/+\\z}, "") == configured.path.sub(%r{/+\\z}, "") &&
        URI.decode_www_form(observed.query.to_s).sort == URI.decode_www_form(configured.query.to_s).sort
    rescue URI::InvalidURIError, ArgumentError
      false
    end

    def result(status, rows, errors, counts, digest, unmatched, fetch_paths, page_counts, page_details)
      Result.new(status: status, rows: rows, errors: errors, counts: counts, digest: digest,
        unmatched_keys: unmatched, fetch_paths: fetch_paths,
        page_counts: page_counts, page_details: page_details)
    end
  end
end
