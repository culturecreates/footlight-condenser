module Distillator
  class WebsiteValidationHistory
    FILTERS = {
      "never_passed" => "Never passed validation",
      "light_only" => "Passed Light only",
      "thorough_passed" => "Passed Thorough",
      "ready" => "Ready",
      "migrated" => "Migrated",
      "changed_since_pass" => "Configuration changed since last pass",
      "latest_failed" => "Latest validation needs attention"
    }.freeze

    Summary = Struct.new(:light, :thorough, :audit, :last_pass, :last_validation, :changed, :covered, :eligible, :milestone, keyword_init: true) do
      def matches?(filter)
        case filter
        when "never_passed" then last_pass.nil?
        when "light_only" then light.positive? && thorough.zero?
        when "thorough_passed" then thorough.positive?
        when "ready", "migrated" then milestone == filter
        when "changed_since_pass" then changed
        when "latest_failed" then last_validation&.status.in?(%w[attention recovery_failed])
        else true
        end
      end
    end

    def self.workflows(website_ids)
      SiteTransition.where(website_id: website_ids).includes(:batch, :pre_run, :post_run)
        .order(Arel.sql("completed_at DESC NULLS LAST"), id: :desc)
    end

    def self.for_websites(websites)
      items = workflows(websites.map(&:id)).where(status: SiteTransition::TERMINAL).to_a.group_by(&:website_id)
      validations = items.transform_values { |rows| rows.reject { |row| row.batch.audit? } }
      passes = validations.transform_values { |rows| rows.select { |row| row.status == "passed" } }
      run_ids = passes.values.flatten.flat_map { |row| [row.pre_run_id, row.post_run_id] }.compact
      evidence = TransitionEvidence.where(transition_run_id: run_ids, check_kind: "fetch_parity").latest_first.pluck(
        :transition_run_id, Arel.sql("details -> 'validation_coverage'"),
        Arel.sql("details -> 'representative_webpages'"), Arel.sql("details ->> 'fetch_basis'")
      ).each_with_object({}) { |(id, *data), out| out[id] ||= data }
      eligible_pages = Webpage.public_publishable_events.active.without_reviewed_transition_exclusions
        .where(website_id: passes.keys.select { |id| passes[id].any? }).group_by(&:website_id)
      library_version = TransitionFingerprint.library_version if run_ids.any?

      websites.to_h do |website|
        passed = passes.fetch(website.id, [])
        counts = passed.map { |row| row.batch.check_profile }.tally
        last = passed.first
        summary = Summary.new(light: counts.fetch("light", 0), thorough: counts.fetch("thorough", 0),
          audit: items.fetch(website.id, []).count { |row| row.batch.audit? && row.status == "passed" },
          last_pass: last, last_validation: validations.fetch(website.id, []).first)
        summary.milestone = milestone(website, summary.thorough)
        if last
          pages = eligible_pages.fetch(website.id, [])
          current_digest, configuration = TransitionFingerprint.for_validation_history(website, library_version: library_version)
          page_digests = pages.to_h { |page| [page.id.to_s, TransitionFingerprint.event_page(page)] }
          summary.eligible = pages.size
          summary.covered = passed.flat_map do |item|
            runs = coverage_runs(item)
            runs.map { |run| covered_pages(run, evidence, pages, page_digests, configuration, current_digest) }
              .reduce(:&) || []
          end.uniq.size
          if (run = last.post_run || last.pre_run)
            recorded_configuration = evidence.dig(run.id, 0, "configuration")
            summary.changed = run.configuration_digest != current_digest ||
              (recorded_configuration.present? && recorded_configuration != configuration)
          end
        end
        [website.id, summary]
      end
    end

    def self.milestone(website, thorough_passes)
      return unless website.distillator_mode == "active" && thorough_passes.positive?

      thorough_passes >= 2 && WebsiteIndexGroups.category(website) == :scheduled ? "migrated" : "ready"
    end

    def self.coverage_runs(item)
      needs_precheck = item.initial_mode != "active" || item.batch.thorough_revalidation? || item.phase_results.key?("precheck")
      return [] unless item.post_run && (!needs_precheck || item.pre_run)

      [item.pre_run, item.post_run].compact
    end

    def self.covered_pages(run, evidence, pages, page_digests, configuration, current_digest)
      snapshot, urls, fetch_basis = evidence[run.id]
      return [] unless run.status == "completed" && fetch_basis == "fresh_both"

      if snapshot
        return [] unless snapshot["configuration"] == configuration

        snapshot.fetch("pages").filter_map { |id, digest| id if page_digests[id] == digest }
      elsif run.configuration_digest == current_digest
        recorded_urls = Array(urls).to_set
        pages.filter_map { |page| page.id.to_s if recorded_urls.include?(page.url) }
      else
        []
      end
    end
    private_class_method :milestone, :coverage_runs, :covered_pages
  end
end
