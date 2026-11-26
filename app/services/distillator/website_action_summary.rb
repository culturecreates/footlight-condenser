module Distillator
  # Operator recommendations from recorded evidence. Workflow admission and
  # migration qualification remain the responsibility of the existing services.
  class WebsiteActionSummary
    FILTERS = {
      "all" => "All actions", "attention" => "Needs attention", "validation" => "Ready for validation",
      "migration" => "Ready for migration", "progress" => "In progress"
    }.freeze

    PRIORITIES = { p0: 0, p1: 1, p2: 2, progress: 3, p3: 4 }.freeze
    Action = Struct.new(:code, :category, :priority, :title, :explanation, :impact, :operation, :evidence, :consequence,
      keyword_init: true) do
      def matches?(filter)
        case filter
        when "attention" then priority.in?(%i[p0 p1 p2]) && code != :validation_required
        when "validation" then operation == :validate
        when "migration" then operation == :confirm_cutover
        when "progress" then category == :progress
        else true
        end
      end

      def rank
        PRIORITIES.fetch(priority)
      end

      def takes_precedence?
        priority.in?(%i[p0 progress])
      end
    end

    def self.running_for(website_ids)
      workflows = SiteTransition.active.where(website_id: website_ids).select(:id, :website_id, :status, :batch_id)
        .includes(:batch).index_by(&:website_id)
      checks = TransitionRun.active.where(website_id: website_ids - workflows.keys)
        .select(:id, :website_id, :status, :check_options).index_by(&:website_id)
      checks.merge(workflows)
    end

    def self.for_websites(websites, inventories:, validations:, eligible_ids:, running:)
      ids = websites.map(&:id)
      seeds = websites.map(&:seedurl)
      issues = MonitoringIssue.open_issues.where(seedurl: seeds).select(:id, :seedurl, :kind, :property_name, :message, :last_seen_at)
        .order(last_seen_at: :desc, id: :desc).group_by(&:seedurl)
      pages = Webpage.event_pages.public_source_urls.active.where(website_id: ids)
      requirements = Events::ResourcePublishability.new(pages).missing_requirements_by_resource
        .reject { |_, fields| fields.empty? }.group_by { |(website_id, _), _| website_id }
      eligible = eligible_ids.to_set
      staging = TransitionRuntime.staging?

      websites.to_h do |website|
        actions = new(website, inventory: inventories.fetch(website.id), validation: validations.fetch(website.id),
          eligible: eligible.include?(website.id), running: running[website.id], issues: issues.fetch(website.seedurl, []),
          requirements: requirements.fetch(website.id, []), staging: staging).call
        [website.id, actions]
      end
    end

    def initialize(website, inventory:, validation:, eligible:, running:, issues: [], requirements: [], staging: false)
      @website = website
      @inventory = inventory
      @validation = validation
      @eligible = eligible
      @running = running
      @issues = issues
      @requirements = requirements
      @staging = staging
    end

    def call
      candidates = [recovery, running, *discovery, data_quality, comparison_attention, monitoring, staging_mode].compact
      if candidates.none? { |item| item.priority.in?(%i[p0 p1]) || item.code == :staging_mode ||
          (item.category == :discovery && !item.evidence[:verified_discovery]) }
        candidates << progression
      end
      candidates.compact.each_with_index.sort_by { |item, index| [item.takes_precedence? ? 0 : 1, item.rank, index] }.map(&:first)
    end

    private

    def action(code, category, priority, title, explanation, impact, operation, evidence: {}, consequence: nil)
      Action.new(code: code, category: category, priority: priority, title: title, explanation: explanation,
        impact: impact, operation: operation, evidence: evidence, consequence: consequence)
    end

    def workflow?(record)
      record.is_a?(SiteTransition)
    end

    def recovery
      item = @validation.attention
      return unless workflow?(item) && item.status == "recovery_failed"

      action(:recovery_failed, :operations, :p0, "Review failed recovery",
        item.reason.presence || "The transition could not confirm recovery.",
        "The serving configuration needs operator review.", :workflow, evidence: { record: item })
    end

    def running
      return unless @running
      audit = workflow?(@running) && @running.batch.audit?
      label = audit ? "Active audit" : (workflow?(@running) ? "Transition workflow" : "Comparison")
      impact = audit ? "The audit keeps the current rollout mode." : "Follow this check before starting another workflow."

      action(audit ? :audit_in_progress : :validation_in_progress, :progress, :progress,
        "#{label} #{@running.status}", nil, impact, workflow?(@running) ? :workflow : :check,
        evidence: { record: @running })
    end

    def discovery
      lists = Array(@inventory[:lists])
      findings = lists.filter_map do |list|
        verified = list[:status] == "event"
        next unless verified || list[:status] == "unverified"
        # Reconciliation is handled below using the website-wide inventory.
        next if list[:next_action].blank? || list[:next_action] == :reconcile_urls

        priority = list[:reason].in?(%i[invalid_or_empty_list extraction_failed source_fetch_failed ambiguous_list]) ? :p1 : :p2
        impact = if !verified
          "This list needs attention before it can provide current discovery evidence."
        elsif priority == :p1
          "The latest failure could affect the next discovery run."
        else
          "Discovery evidence remains verified. Maintenance supports the next discovery run."
        end
        title = if verified && priority == :p2
          "ResourceList maintenance · #{ResourceListReadiness::ACTIONS.fetch(list[:next_action])}"
        else
          "Review ResourceList discovery"
        end
        action(list[:reason], :discovery, priority, title, list[:message], impact, :resource_list,
          evidence: { webpage_id: list[:webpage_id], next_action: list[:next_action], verified_discovery: verified })
      end
      if @inventory[:pending_import]
        list = lists.find { |row| row.dig(:reconciliation, :missing_urls).to_i.positive? && row.dig(:reconciliation, :state) == :pending }
        findings << action(:pending_reconciliation, :discovery, :p2, "New event URLs need reconciliation",
          "Discovered URLs are missing from the event inventory.",
          "Newly discovered events must be accounted for before qualifying.", list ? :resource_list : :details,
          evidence: { webpage_id: list&.dig(:webpage_id), next_action: :reconcile_urls })
      end
      findings
    end

    def data_quality
      listed = Array(@inventory[:unpublishable_listed_pages]).map { |page| page[:rdf_uri] }.to_set
      listed_requirements = @requirements.select { |(_, uri), _| listed.include?(uri) }
      (site_and_uri, fields) = (listed_requirements.presence || @requirements).first
      return unless site_and_uri

      uri = site_and_uri.last
      names = fields.pluck(:field).to_sentence
      blocking = listed.include?(uri)
      explanation = fields.flat_map { |field| field.fetch(:reasons) }.to_sentence
      action(:missing_event_fields, :data_quality, blocking ? :p1 : :p2, "Missing required event fields",
        "#{names} unavailable for an active event. #{explanation}.",
        blocking ? "Listed events lack required statements for validation." : "The affected event cannot be published.",
        :event_statements, evidence: { rdf_uri: uri, fields: fields, event_count: @requirements.size })
    end

    def comparison_attention
      item = @validation.attention
      return if !item || (workflow?(item) && item.status == "recovery_failed")

      if workflow?(item)
        audit = item.batch.audit?
        title = audit ? "Active audit needs review" : "Transition workflow needs review"
        title = "#{title} (previous run)" if @running
        impact = audit ? "Review the audit findings while keeping the current rollout mode." : "Review the recorded checks before starting another transition."
        action(audit ? :audit_attention : :workflow_attention, :validation, audit ? :p2 : :p1, title,
          item.reason.presence, impact, :workflow, evidence: { record: item })
      else
        failed = item.status == "failed"
        title = failed ? "Comparison did not complete" : "Comparison needs review"
        title = "#{title} (previous run)" if @running
        action(failed ? :comparison_failed : :comparison_needs_review, :validation, :p1,
          title, item.error_message.presence,
          "Review the recorded result before starting another comparison.", :check, evidence: { record: item })
      end
    end

    def monitoring
      issue = @issues.find { |record| record.kind == "blocked_fetch" } || @issues.find do |record|
        record.kind != "listed_event_unpublishable" &&
          (!record.kind.in?(%w[resource_list_refresh resource_list_import_incomplete]) || @website.refresh_scheduled?)
      end
      return unless issue

      blocked = issue.kind == "blocked_fetch"
      action(blocked ? :source_fetch_blocked : :monitoring_issue, :operations, blocked ? :p1 : :p2,
        blocked ? "Monitor reports a blocked source fetch" : "Review open monitoring issue", issue.message,
        blocked ? "The affected source needs review." : "Review the recorded operational evidence.",
        :monitoring, evidence: { issue_id: issue.id, last_seen_at: issue.last_seen_at })
    end

    def staging_mode
      return unless @staging && TransitionRuntime.staging_rollout_mode_invalid?(@website.distillator_mode)

      explanation = @website.distillator_mode == "legacy" ? "This site is in Legacy mode." : "This site has an unset or unsupported rollout mode."
      action(:staging_mode, :operations, :p2, "Review staging rollout mode", explanation,
        "Staging expects Shadow or Active.", :website)
    end

    def progression
      return if @running || !@eligible || @validation.milestone == "migrated"

      if @validation.milestone == "ready" && @validation.confirmable_cutover?
        return action(:confirm_cutover, :migration, :p3, "Ready for cutover confirmation",
          "The site has qualifying Thorough evidence.", "Record migration after Artsdata receives the Condenser export.",
          :confirm_cutover, consequence: "Have the Artsdata import reference and handoff time available.")
      end

      readiness = ResourceListReadiness.validation(@validation, @inventory)
      if @inventory[:status].in?(%w[no_discovery_lists no_event_discovery])
        readiness = ResourceListReadiness.guidance(@inventory[:status])
      end
      if readiness[:next_action] == :review_list_configuration
        return action(readiness[:reason], :discovery, :p2, "Review discovery configuration", readiness[:message],
          "Current discovery evidence is needed for Ready qualification.", :details)
      end

      outdated = @validation.latest_thorough && (@validation.changed ||
        readiness[:reason].in?(%i[current_scope_unverified discovery_configuration_changed]))
      explanation = if outdated
        "The previous Thorough evidence no longer covers the current inventory or configuration."
      else
        readiness[:message] || "No qualifying Thorough comparison is recorded for this site."
      end
      action(outdated ? :validation_outdated : :validation_required, :validation, :p2,
        outdated ? "Thorough evidence outdated" : "Thorough validation needed", explanation,
        "Ready qualification pending.", :validate,
        evidence: { eligible_pages: @validation.eligible, last_pass_at: @validation.latest_thorough&.completed_at,
          readiness_reason: readiness[:reason] },
        consequence: ("Thorough validation may temporarily move the site from Active to Shadow." if @website.distillator_mode == "active"))
    end
  end
end
