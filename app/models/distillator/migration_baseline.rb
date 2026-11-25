module Distillator
  class MigrationBaseline < ApplicationRecord
    self.table_name = "distillator_migration_baselines"

    belongs_to :website
    belongs_to :validation_run, class_name: "Distillator::TransitionRun", optional: true

    scope :latest_first, -> { order(validated_at: :desc, validation_run_id: :desc) }

    def readonly?
      persisted? || super
    end

    def self.latest_for_websites(website_ids)
      where(website_id: website_ids).select("DISTINCT ON (website_id) distillator_migration_baselines.*")
        .order(:website_id).latest_first.includes(:validation_run).index_by(&:website_id)
    end

    def self.capture!(website, validation_run_id: nil)
      return unless website.distillator_mode == "active" && (website.refresh_scheduled? || validation_run_id)

      website.with_lock do
        return unless website.distillator_mode == "active"

        previous = where(website_id: website.id).latest_first.first
        return unless previous || website.refresh_scheduled?
        return if previous && !validation_run_id
        return if !validation_run_id && SiteTransition.active.exists?(website_id: website.id)

        inventories = WebsiteInventoryFreshness.for_websites([website.id])
        candidate = WebsiteValidationHistory.for_websites([website], inventories: inventories).fetch(website.id).migration_candidate
        return unless candidate
        return if validation_run_id && candidate[:validation_run_id] != validation_run_id
        if previous
          return unless ([candidate[:validated_at], candidate[:validation_run_id]] <=>
            [previous.validated_at, previous.validation_run_id]).positive?
        end

        create!(website: website, **candidate)
      end
    end

    def covered_pages
      page_fingerprints.size
    end
  end
end
