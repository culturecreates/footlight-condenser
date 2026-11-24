require "digest"
require "json"

module Distillator
  class TransitionFingerprint
    STALE_MESSAGE = "Comparison configuration changed since the last check (source settings or DSL execution contract). Run a new check.".freeze
    def self.call(website)
      full_digest(website, configuration_inputs(website))
    end

    def self.for_validation_history(website, library_version:)
      inputs = configuration_inputs(website)
      [full_digest(website, inputs), digest([inputs, library_version])]
    end

    def self.full_digest(website, inputs)
      # Hash values as well as timestamps: older tables only store whole seconds.
      # Include insertions/deletions and the metadata used to interpret DSL values.
      # Cached-legacy comparisons cannot qualify under the fresh-on-both-sides policy.
      settings = ["fresh_both_page_fetch_v3_active_events", *inputs]
      pages = website.webpages.order(:id).pluck(*page_columns)
      recorded_digest(settings, pages, current_exclusions(website))
    end

    def self.after_discovery(website, expected_digest:, discovery:)
      columns = page_columns
      id_column = columns.index("id")
      archive_column = columns.index("archive_date")
      settings = ["fresh_both_page_fetch_v3_active_events", *configuration_inputs(website)]
      pages = website.webpages.order(:id).pluck(*columns)
      exclusions = current_exclusions(website)
      added = discovery.added_page_ids.to_set
      previous_dates = discovery.prior_archive_dates
      previous_pages = pages.filter_map do |page|
        id = page[id_column]
        next if added.include?(id)
        next page unless previous_dates.key?(id)

        page.dup.tap { |row| row[archive_column] = previous_dates[id] }
      end
      return unless expected_digest == recorded_digest(settings, previous_pages, exclusions)

      recorded_digest(settings, pages, exclusions)
    end

    def self.page_columns
      Webpage.column_names - ["discovery_target_website_id"]
    end

    def self.current_exclusions(website)
      website.transition_exclusions.active.order(:id).pluck(:id, :url, :reason, :source_run_id, :created_at)
    end

    def self.recorded_digest(settings, pages, exclusions)
      inputs = [*settings, pages]
      inputs << ["reviewed_transition_exclusions_v1", exclusions] if exclusions.any?
      digest(inputs)
    end

    def self.configuration(website, library_version: self.library_version)
      digest([configuration_inputs(website), library_version])
    end

    def self.library_version
      digest(DslLibraryEntry.order(:id).pluck(:id, :revision))
    end

    def self.event_page(page)
      columns = %w[url language rdf_uri rdfs_class_id archive_date jsonld_output_id]
      digest(columns.map { |column| page.attribute_in_database(column) })
    end

    def self.configuration_inputs(website)
      inputs = [["dsl_contract", Dsl::Core::AlgorithmRunner::CONTRACT_VERSION], website.attributes.slice("seedurl", "default_language", "graph_name"),
        website.sources.order(:id).pluck(*Source.column_names),
        Property.where(id: website.sources.select(:property_id)).order(:id).pluck(*Property.column_names),
        RdfsClass.order(:id).pluck(:id, :name)]
      if Webpage.where(discovery_target_website_id: website.id).exists?
        inputs << ["linked_discovery", TransitionEventInventory.definition_digest(website.id)]
      end
      inputs
    end

    def self.digest(values)
      Digest::SHA256.hexdigest(JSON.generate(values))
    end

    private_class_method :full_digest, :page_columns, :current_exclusions, :recorded_digest, :configuration_inputs, :digest
  end
end
