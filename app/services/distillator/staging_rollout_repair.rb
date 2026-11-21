module Distillator
  class StagingRolloutRepair
    WebsiteSummary = Struct.new(:id, :name, :seedurl, :mode, keyword_init: true)

    Result = Struct.new(
      :dry_run,
      :applied,
      :invalid_count,
      :repaired_count,
      :websites,
      :changed_websites,
      :unchanged_websites,
      :errors,
      keyword_init: true
    ) do
      def success?
        errors.blank?
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(apply: false, actor: "staging_rollout_repair", reason: "Staging rollout repair")
      @apply = apply
      @actor = actor
      @reason = reason
    end

    def call
      invalid_websites = scoped_invalid_websites
      summaries = invalid_websites.map { |website| website_summary(website) }

      return dry_run_result(summaries) unless apply?
      return failure_result(summaries, "Staging rollout repair can only run on staging.") unless Distillator::TransitionRuntime.staging?

      repaired_count = 0
      errors = []
      changed_websites = []
      unchanged_websites = []

      invalid_websites.each do |website|
        result = Distillator::RolloutTransition.call(
          website: website,
          to_mode: "shadow",
          actor: actor,
          reason: reason
        )

        if result.success?
          repaired_count += 1
          changed_websites << website_summary(website.reload)
        else
          errors << "#{website.id} #{website.name}: #{result.errors.join(', ')}"
          unchanged_websites << website_summary(website)
        end
      end

      Result.new(
        dry_run: false,
        applied: true,
        invalid_count: summaries.length,
        repaired_count: repaired_count,
        websites: summaries,
        changed_websites: changed_websites,
        unchanged_websites: unchanged_websites,
        errors: errors
      )
    end

    private

    attr_reader :actor, :reason

    def apply?
      @apply == true
    end

    def scoped_invalid_websites
      Distillator::TransitionRuntime.staging_invalid_rollout_mode_scope.order(:id).to_a
    end

    def website_summary(website)
      WebsiteSummary.new(
        id: website.id,
        name: website.name,
        seedurl: website.seedurl,
        mode: website.distillator_mode.presence || "blank"
      )
    end

    def dry_run_result(summaries)
      Result.new(
        dry_run: true,
        applied: false,
        invalid_count: summaries.length,
        repaired_count: 0,
        websites: summaries,
        changed_websites: [],
        unchanged_websites: summaries,
        errors: []
      )
    end

    def failure_result(summaries, error)
      Result.new(
        dry_run: false,
        applied: false,
        invalid_count: summaries.length,
        repaired_count: 0,
        websites: summaries,
        changed_websites: [],
        unchanged_websites: summaries,
        errors: [error]
      )
    end
  end
end
