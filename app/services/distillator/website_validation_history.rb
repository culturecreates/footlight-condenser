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

    READY_THOROUGH_PASSES = 2
    MIGRATED_THOROUGH_PASSES = 2 * READY_THOROUGH_PASSES
    Pass = Struct.new(:profile, :completed_at, :runs, :workflow, :site_check, keyword_init: true)

    Summary = Struct.new(:light, :thorough, :audit, :last_pass, :last_validation, :changed, :covered, :eligible, :milestone, keyword_init: true) do
      def matches?(filter)
        case filter
        when "never_passed" then last_pass.nil?
        when "light_only" then light.positive? && thorough.zero?
        when "thorough_passed" then thorough.positive?
        when "ready", "migrated" then milestone == filter
        when "changed_since_pass" then changed
        when "latest_failed"
          last_validation&.status.in?(%w[attention recovery_failed]) &&
            !(last_pass&.site_check && last_validation.completed_at && last_pass.completed_at > last_validation.completed_at)
        else true
        end
      end
    end

    def self.workflows(website_ids)
      SiteTransition.where(website_id: website_ids).includes(:batch, :pre_run, :post_run)
        .order(Arel.sql("completed_at DESC NULLS LAST"), id: :desc)
    end

    def self.site_check_passes(websites)
      by_website = websites.index_by(&:id)
      workflow_items = SiteTransition.where(website_id: by_website.keys)
      checked_exports = TransitionEvidence.where(website_id: by_website.keys, check_kind: "export_diff",
        status: "checked", export_diff_checked: true).select(:transition_run_id)
      TransitionRun.current_checks.completed.where(website_id: by_website.keys).where.not(completed_at: nil)
        .where(id: checked_exports)
        .where.not(id: workflow_items.where.not(pre_run_id: nil).select(:pre_run_id))
        .where.not(id: workflow_items.where.not(post_run_id: nil).select(:post_run_id))
        .includes(:transition_evidences).order(completed_at: :desc, id: :desc).filter_map do |run|
          profile = site_check_profile(run)
          next unless profile

          verdict = TransitionStatus.for_completed_run(website: by_website.fetch(run.website_id), run: run)
          next unless verdict.status == :ready && [verdict.fetch, verdict.statements, verdict.export].all?(:passed)

          Pass.new(profile: profile, completed_at: run.completed_at, runs: [run], site_check: run)
        end
    end

    def self.for_websites(websites, inventories: {})
      items = workflows(websites.map(&:id)).where(status: SiteTransition::TERMINAL).to_a.group_by(&:website_id)
      validations = items.transform_values { |rows| rows.reject { |row| row.batch.audit? } }
      passes = validations.transform_values do |rows|
        rows.select { |row| row.status == "passed" }.map do |row|
          Pass.new(profile: row.batch.check_profile, completed_at: row.completed_at, runs: coverage_runs(row), workflow: row)
        end
      end
      site_check_passes(websites).each do |pass|
        (passes[pass.site_check.website_id] ||= []) << pass
      end
      run_ids = passes.values.flatten.flat_map { |pass| pass.runs.map(&:id) }
      evidence = TransitionEvidence.where(transition_run_id: run_ids, check_kind: "fetch_parity").latest_first.pluck(
        :transition_run_id, Arel.sql("details -> 'validation_coverage'"),
        Arel.sql("details -> 'representative_webpages'"), Arel.sql("details ->> 'fetch_basis'")
      ).each_with_object({}) { |(id, *data), out| out[id] ||= data }
      eligible_pages = Webpage.public_publishable_events.active.without_reviewed_transition_exclusions
        .where(website_id: passes.keys.select { |id| passes[id].any? }).group_by(&:website_id)
      library_version = TransitionFingerprint.library_version if run_ids.any?

      websites.to_h do |website|
        passed = passes.fetch(website.id, [])
        counts = passed.map(&:profile).tally
        last = passed.max_by { |pass| pass.completed_at || Time.at(0) }
        summary = Summary.new(light: counts.fetch("light", 0), thorough: counts.fetch("thorough", 0),
          audit: items.fetch(website.id, []).count { |row| row.batch.audit? && row.status == "passed" },
          last_pass: last, last_validation: validations.fetch(website.id, []).first)
        summary.milestone = milestone(website, passed, inventories[website.id])
        if last
          pages = eligible_pages.fetch(website.id, [])
          current_digest, configuration = TransitionFingerprint.for_validation_history(website, library_version: library_version)
          page_digests = pages.to_h { |page| [page.id.to_s, TransitionFingerprint.event_page(page)] }
          summary.eligible = pages.size
          summary.covered = passed.flat_map do |pass|
            pass.runs.map { |run| covered_pages(run, evidence, pages, page_digests, configuration, current_digest) }
              .reduce(:&) || []
          end.uniq.size
          if (run = last.runs.last || last.workflow&.post_run || last.workflow&.pre_run)
            recorded_configuration = evidence.dig(run.id, 0, "configuration")
            summary.changed = run.configuration_digest != current_digest ||
              (recorded_configuration.present? && recorded_configuration != configuration)
          end
        end
        [website.id, summary]
      end
    end

    def self.site_check_profile(run)
      fetch = run.transition_evidences.find { |row| row.check_kind == "fetch_parity" }
      details = fetch&.details.to_h
      return unless details["fetch_basis"] == "fresh_both" && details.dig("event_inventory", "status") == "active_event_scope"

      checked = details["representative_webpage_count"].to_i
      return unless checked.positive?

      options = run.options
      return "light" if options.default?
      return unless options.strict? && options.sample_mode.in?(%w[all count])

      "thorough" if checked == details["publishable_event_page_count"].to_i
    end

    def self.milestone(website, passes, inventory)
      return unless website.distillator_mode == "active" && WebsiteIndexGroups.category(website) == :scheduled
      return unless inventory&.dig(:status) == "confirmed_discovery" && inventory[:verified_list_refresh_at].present?

      refreshed_at = Time.iso8601(inventory.fetch(:verified_list_refresh_at))
      thorough_passes = passes.count do |pass|
        pass.profile == "thorough" && pass.runs.any? && pass.runs.all? { |run| verified_before_check?(run, refreshed_at) }
      end
      return "migrated" if thorough_passes >= MIGRATED_THOROUGH_PASSES

      "ready" if thorough_passes >= READY_THOROUGH_PASSES
    end

    def self.verified_before_check?(run, refreshed_at)
      if run.progress.key?("discovery_at_start")
        run.progress["discovery_at_start"] == "confirmed_discovery"
      else
        started_at = run.started_at || run.requested_at
        refreshed_at <= started_at && refreshed_at >= started_at - TransitionEventInventory::MAX_LIST_AGE
      end
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
    private_class_method :site_check_profile, :milestone, :verified_before_check?, :coverage_runs, :covered_pages
  end
end
