# frozen_string_literal: true

require "digest"
require "json"

module ResourceLists
  # Explicit, offline QA adapter. Both calendar snapshots are validated before
  # any ResourceList statement or event page changes. This is NOT a scheduled
  # production refresh and does not attest to live pagination completeness.
  class DanseDanseKeyedQaRefresh
    Invalid = Class.new(StandardError)
    ROOT = "https://www.dansedanse.ca"
    LANGUAGES = {
      "en" => { path: "/en/shows", category: "Show" },
      "fr" => { path: "/fr/spectacles", category: "Spectacle" }
    }.freeze
    LABELS = ["Webpage URL List", "URI List"].freeze
    Result = Struct.new(:status, :pair_count, :digest, :imported_ids, keyword_init: true)

    # The DSL step can only read an already validated, in-memory bilingual run.
    class Context
      attr_reader :website_id

      def initialize(website_id:, values:)
        @website_id = website_id
        @values = values.transform_values { |rows| rows.transform_values { |items| items.dup.freeze }.freeze }.freeze
      end

      def read(kind, language)
        raise Invalid, "Invalid calendar language" unless LANGUAGES.key?(language)
        raise Invalid, "Invalid calendar output" unless %w[urls uris].include?(kind)

        @values.fetch(language).fetch(kind).dup
      end
    end

    def self.call(website:, html_pages:, expected_manifest:, apply: false)
      new(website: website, html_pages: html_pages, expected_manifest: expected_manifest).call(apply: apply)
    end

    def initialize(website:, html_pages:, expected_manifest:)
      @website = website
      @html_pages = html_pages
      @manifest = expected_manifest
    end

    def call(apply: false)
      return execute(apply: false) unless apply

      Website.transaction do
        @website.lock!
        execute(apply: true)
      end
    end

    private

    def execute(apply:)
      check_qa_site!
      alignment = extract_alignment!
      check_manifest!(alignment)
      pages = validate_existing_pairs!(alignment)
      list_pages = discover_list_pages!
      context = Context.new(website_id: @website.id, values: LANGUAGES.keys.to_h do |lang|
        [lang, { "urls" => alignment.paired_urls_for(lang),
                 "uris" => alignment.pairs.map { |pair| pages.fetch(pair.key) } }]
      end)
      payloads = LANGUAGES.keys.to_h do |lang|
        page = list_pages.fetch(lang)
        statements = payload_statements!(page)
        values = { "Webpage URL List" => execute_dsl!(context, page, "urls", lang),
                   "URI List" => execute_dsl!(context, page, "uris", lang) }
        [lang, { page: page, statements: statements, values: values }]
      end

      imported = []
      if apply
        now = Time.current
        payloads.each_value do |entry|
          entry.fetch(:statements).each do |label, statement|
            cache = JSON.generate(entry.fetch(:values).fetch(label))
            changes = { cache: cache, cache_refreshed: now, status: "updated",
              updated_at: now, fetch_provenance: {} }
            changes[:cache_changed] = now if statement.cache != cache
            statement.update_columns(changes)
          end
        end
        # Reuse the real import validation, with no refresh queueing; both
        # languages run within the single outer transaction.
        payloads.each_value do |entry|
          imported.concat(Array(AddWebpagesJob.perform_now(entry.fetch(:page).id,
            selected_only: true, refresh_new: false)))
        end
        # This tranche tests exact parity of the *existing* eight bilingual pairs.
        # A new event needs a separate reviewed URI-minting contract.
        raise Invalid, "Unexpected new webpages in baseline-only QA import" if imported.any?
      end

      Result.new(status: apply ? "applied" : "validated", pair_count: alignment.pairs.size,
        digest: alignment.digest, imported_ids: imported)
    end

    def check_qa_site!
      raise Invalid, "QA copy must be saved" unless @website&.persisted?
      unless @website.seedurl == "dansedansetest-ca" &&
          @website.test_copy_of_website&.seedurl == "dansedanse-ca" &&
          @website.distillator_mode == "shadow" && !@website.refresh_scheduled?
        raise Invalid, "Only the unscheduled Danse Danse shadow QA copy is eligible"
      end
    end

    def extract_alignment!
      raise Invalid, "Both calendar languages are required" unless @html_pages.is_a?(Hash) &&
        @html_pages.keys.sort == LANGUAGES.keys.sort

      streams = LANGUAGES.to_h do |language, configuration|
        documents = @html_pages.fetch(language)
        raise Invalid, "Missing #{language} calendar snapshot" unless documents.is_a?(Array) && documents.any?
        item_xpath = "//div[contains(@class,'section--listing-spectacles__container')]" \
          "//div[contains(concat(' ',normalize-space(@class),' '),' block--spectacle ')]" \
          "[.//div[contains(@class,'block--spectacle__title--info--category')]/span[normalize-space(.)='#{configuration.fetch(:category)}']]"
        records = documents.each_with_index.flat_map do |html, index|
          result = KeyedCalendarExtractor.call(html: html, base_url: ROOT + configuration.fetch(:path),
            item_xpath: item_xpath, url_xpath: "./a[1]/@href", key_xpath: "./a[1]/@href",
            key_mode: :url_last_segment)
          raise Invalid, "#{language} calendar #{index}: #{result.errors.join(', ')}" unless result.valid?
          result.records
        end
        [language, records]
      end
      alignment = KeyedCalendarAlignment.call(streams: streams)
      raise Invalid, "Bilingual calendar incomplete or invalid: #{alignment.errors.inspect}; unmatched=#{alignment.unmatched.map(&:key)}" unless
        alignment.complete? && alignment.languages == LANGUAGES.keys.sort && alignment.pairs.any?
      alignment
    end

    def check_manifest!(alignment)
      raise Invalid, "Expected a reviewed QA manifest" unless @manifest.is_a?(Hash) &&
        @manifest["seedurl"] == @website.seedurl &&
        @manifest["status"] == "ready_for_review" &&
        @manifest["alignment_digest"] == alignment.digest &&
        @manifest["pair_count"] == alignment.pairs.size &&
        @manifest["conflicts"] == [] &&
        @manifest["unmatched_translation_keys"] == [] &&
        @manifest["currently_missing_webpages"] == [] &&
        @manifest["removed_vs_source_1340"] == [] &&
        @manifest["added_vs_source_1340"] == []
      expected = @manifest.fetch("pairs").map { |row| [row.fetch("key"), row.fetch("urls")] }.sort_by(&:first)
      actual = alignment.pairs.map { |pair| [pair.key, pair.urls] }.sort_by(&:first)
      raise Invalid, "Reviewed manifest does not match current HTML" unless expected == actual
    end

    def validate_existing_pairs!(alignment)
      urls = alignment.pairs.flat_map { |pair| pair.urls.values }
      found = @website.webpages.event_pages.where(url: urls).to_a
      by_url = found.index_by(&:url)
      raise Invalid, "All paired URLs must already exist in this baseline trial" unless by_url.size == urls.size

      alignment.pairs.to_h do |pair|
        rows = pair.urls.map do |lang, url|
          page = by_url.fetch(url)
          raise Invalid, "Language mismatch: #{url}" unless page.language == lang
          page
        end
        uris = rows.map(&:rdf_uri).uniq
        if uris.size != 1 || !uris.first.start_with?("http://kg.footlight.io/resource/#{@website.seedurl}_")
          raise Invalid, "Conflicting or non-QA RDF identity: #{pair.key}"
        end
        manifest_uri = @manifest.fetch("pairs").find { |row| row["key"] == pair.key }.fetch("existing_rdf_uri")
        raise Invalid, "RDF identity changed since manifest: #{pair.key}" unless uris.first == manifest_uri

        [pair.key, uris.first]
      end
    end

    def discover_list_pages!
      klass = RdfsClass.find_by!(name: "ResourceList")
      LANGUAGES.to_h do |lang, configuration|
        scope = @website.webpages.where(rdfs_class_id: klass.id, language: lang, url: ROOT + configuration.fetch(:path))
        raise Invalid, "Expected one #{lang} ResourceList webpage, found #{scope.count}" unless scope.count == 1
        page = scope.first
        raise Invalid, "Cross-site ResourceList target is not supported" if page.discovery_target_website_id.present?
        [lang, page]
      end
    end

    def payload_statements!(page)
      grouped = page.statements.joins(source: :property)
        .where(selected_individual: true, sources: { selected: true, website_id: @website.id },
          properties: { label: LABELS }).includes(source: :property).group_by { |row| row.source.property.label }
      LABELS.to_h do |label|
        matches = grouped.fetch(label, [])
        raise Invalid, "Expected one selected #{label} for ResourceList #{page.id}" unless matches.one?
        statement = matches.first
        raise Invalid, "Manual #{label} override on ResourceList #{page.id}" if statement.manual?
        [label, statement]
      end
    end

    def execute_dsl!(context, page, kind, lang)
      runner = Dsl::Core::AlgorithmRunner.new(
        url: page.url, render_js: false,
        scrape_options: { website: @website, keyed_calendar_context: context },
        tracer: Dsl::Tracing::NullTracer.new
      )
      value = runner.run("get_sorted_calendars=#{kind},#{lang}")
      raise Invalid, "Keyed DSL failed for #{lang}/#{kind}: #{value.inspect}" unless
        value.is_a?(Array) && value.all? { |item| item.is_a?(String) && item.present? }
      value
    end
  end
end
