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
      inputs = ["fresh_both_page_fetch_v3_active_events", *inputs,
        website.webpages.order(:id).pluck(*Webpage.column_names)]
      exclusions = website.transition_exclusions.active.order(:id).pluck(:id, :url, :reason, :source_run_id, :created_at)
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
      [["dsl_contract", Dsl::Core::AlgorithmRunner::CONTRACT_VERSION], website.attributes.slice("seedurl", "default_language", "graph_name"),
        website.sources.order(:id).pluck(*Source.column_names),
        Property.where(id: website.sources.select(:property_id)).order(:id).pluck(*Property.column_names),
        RdfsClass.order(:id).pluck(:id, :name)]
    end

    def self.digest(values)
      Digest::SHA256.hexdigest(JSON.generate(values))
    end

    private_class_method :full_digest, :configuration_inputs, :digest
  end
end
