require "digest"
require "json"

module Distillator
  class TransitionFingerprint
    def self.call(website)
      # Hash values as well as timestamps: older tables only store whole seconds.
      # Include insertions/deletions and the metadata used to interpret DSL values.
      # Cached-legacy comparisons cannot qualify under the fresh-on-both-sides policy.
      inputs = ["fresh_both_v1", website.attributes.slice("seedurl", "default_language", "graph_name"),
        website.sources.order(:id).pluck(*Source.column_names),
        Property.where(id: website.sources.select(:property_id)).order(:id).pluck(*Property.column_names),
        RdfsClass.order(:id).pluck(:id, :name),
        website.webpages.order(:id).pluck(*Webpage.column_names)]
      exclusions = website.transition_exclusions.active.order(:id).pluck(:id, :url, :reason, :source_run_id, :created_at)
      inputs << ["reviewed_transition_exclusions_v1", exclusions] if exclusions.any?
      Digest::SHA256.hexdigest(JSON.generate(inputs))
    end
  end
end
