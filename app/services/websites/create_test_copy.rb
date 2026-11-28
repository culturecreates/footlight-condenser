# frozen_string_literal: true

require "digest"
require "json"

module Websites
  # Disposable, non-publishing, unscheduled copy for validating DSL changes.
  # This is NOT a production site migration tool.
  class CreateTestCopy
    class InvalidCopy < StandardError; end
    Result = Struct.new(:website, :source_map, :webpage_map, :rdf_uri_map, keyword_init: true)

    def self.suggest_seedurl(seedurl)
      parts = seedurl.to_s.split("-")
      return "#{seedurl}test" if parts.size < 2

      parts[-2] = "#{parts[-2]}test"
      parts.join("-")
    end

    def self.test_uri(original, seedurl:)
      "http://kg.footlight.io/resource/#{seedurl}_#{Digest::SHA256.hexdigest(original.to_s).first(24)}"
    end

    def self.call(source:, seedurl: suggest_seedurl(source.seedurl))
      new(source: source, seedurl: seedurl).call
    end

    def initialize(source:, seedurl:)
      @source = source
      @seedurl = seedurl.to_s.strip.downcase
    end

    def call
      raise InvalidCopy, "Original website is required" unless @source&.persisted?
      raise InvalidCopy, "Invalid test seedurl" unless @seedurl.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
      raise InvalidCopy, "Test seedurl must differ from original" if @seedurl == @source.seedurl
      raise InvalidCopy, "Test seedurl already exists" if Website.exists?(seedurl: @seedurl)
      raise InvalidCopy, "Cannot clone a test copy as another test copy" if @source.test_copy_of_website_id.present?

      Website.transaction do
        # Hold the original website row while taking a consistent model snapshot.
        @source.lock!
        pages = @source.webpages.includes(:rdfs_class).order(:id).to_a
        sources = @source.sources.order(:id).to_a
        statements = Statement.where(webpage_id: pages.map(&:id)).order(:id).to_a
        raise InvalidCopy, "Statements refer to sources outside the original website" unless (statements.map(&:source_id).uniq - sources.map(&:id)).empty?
        raise InvalidCopy, "Cross-site ResourceList targets need explicit mapping" if pages.any? { |page| page.discovery_target_website_id.present? }

        uris = pages.map(&:rdf_uri).uniq
        uri_map = uris.to_h { |uri| [uri, test_uri(uri)] }
        raise InvalidCopy, "URI namespace collision" if Webpage.where(rdf_uri: uri_map.values).exists?

        website_attributes = {
          name: "#{@source.name} [QA copy]",
          seedurl: @seedurl,
          graph_name: @source.graph_name,
          default_language: @source.default_language,
          test_copy_of_website: @source,
          monitorable: false, preferred: false,
          schedule_every_days: nil, schedule_time: nil, last_refresh: nil,
          distillator_mode: "shadow", transition_check_requested_at: nil
        }
        # Some staging snapshots predate the optional place-reconciliation fields.
        # Preserve them when installed, without requiring unrelated migrations.
        %w[province city].each do |column|
          website_attributes[column] = @source[column] if Website.column_names.include?(column)
        end
        copy = Website.create!(website_attributes)

        source_map = sources.to_h do |src|
          cloned = copy.sources.create!(src.attributes.except("id", "website_id", "created_at", "updated_at"))
          [src.id, cloned.id]
        end
        page_map = pages.to_h do |page|
          attributes = page.attributes.except("id", "website_id", "created_at", "updated_at",
            "discovery_target_website_id", "rdf_uri", "url")
          url = page.url == page.rdf_uri ? uri_map.fetch(page.rdf_uri) : page.url
          cloned = copy.webpages.create!(attributes.merge("url" => url, "rdf_uri" => uri_map.fetch(page.rdf_uri)))
          cloned.update_column(:archive_date, page.archive_date) if page.archive_date.nil?
          [page.id, cloned.id]
        end

        # insert_all! avoids status/date callbacks rewriting the imported baseline.
        now = Time.current
        statements.each_slice(500) do |batch|
          Statement.insert_all!(batch.map do |stat|
            stat.attributes.except("id", "created_at", "updated_at").merge(
              "source_id" => source_map.fetch(stat.source_id),
              "webpage_id" => page_map.fetch(stat.webpage_id),
              "cache" => map_cache(stat.cache, uri_map),
              "fetch_provenance" => {},
              "created_at" => now, "updated_at" => now
            )
          end)
        end
        Result.new(website: copy, source_map: source_map, webpage_map: page_map, rdf_uri_map: uri_map)
      end
    end

    private

    def test_uri(original)
      # Namespaced by the selected seedurl, deterministic per original URI;
      # same original RDF URI across FR/EN pages => same cloned URI.
      self.class.test_uri(original, seedurl: @seedurl)
    end

    def map_cache(cache, map)
      return cache if cache.nil?
      parsed = JSON.parse(cache)
      JSON.generate(map_value(parsed, map))
    rescue JSON::ParserError
      map.fetch(cache, cache)
    end

    def map_value(value, map)
      case value
      when String then map.fetch(value, value)
      when Array then value.map { |item| map_value(item, map) }
      when Hash then value.transform_values { |item| map_value(item, map) }
      else value
      end
    end
  end
end
