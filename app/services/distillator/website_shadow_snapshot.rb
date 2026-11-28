# frozen_string_literal: true

require "json"

module Distillator
  # Captures site-level final state for comparison. Run each capture in a separate
  # copy of the same staging DB. Intentionally ignores volatile cache timestamps,
  # ResourceList DSL sources (the candidate configuration), and statement row IDs.
  class WebsiteShadowSnapshot
    def self.call(seedurl: "dansedanse-ca")
      site = Website.find_by!(seedurl: seedurl)
      pages = site.webpages.includes(:rdfs_class).order(:url).to_a
      events = pages.reject { |page| page.rdfs_class.name == "ResourceList" }
      sources = site.sources.includes(property: :rdfs_class).to_a
      event_sources = sources.reject { |source| source.property.rdfs_class.name == "ResourceList" }
        .map { |source| source.attributes.except("created_at", "updated_at") }
        .sort_by { |row| row.fetch("id") }
      selected = Statement.where(webpage_id: events.map(&:id), selected_individual: true).includes(:source).to_a
      pages_by_id = events.index_by(&:id)
      statements = selected.map do |statement|
        page = pages_by_id.fetch(statement.webpage_id)
        [page.url, page.rdf_uri, statement.source_id, statement.source.language.to_s,
         statement.cache, statement.status, statement.manual, statement.selected_individual]
      end.sort_by { |row| [row[0], row[2]] }

      # JSON round-trip normalizes Rails Time/Date and DB scalar serialization.
      JSON.parse(JSON.generate({
        "schema_version" => 1,
        "test_copy_origin_seedurl" => site.test_copy_of_website&.seedurl,
        "website" => site.attributes.slice("name", "seedurl", "graph_name", "default_language"),
        "event_sources" => event_sources,
        "webpages" => pages.map { |page| [page.url, page.rdf_uri, page.language.to_s,
          page.rdfs_class.name, page.archive_date&.utc&.iso8601] }.sort_by(&:first),
        "statements" => statements,
        "export_jsonld" => ExportArtsdataService.call(seedurl: site.seedurl)
      }))
    end
  end
end
