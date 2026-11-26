module Distillator
  class ResourceListReadiness
    GUIDANCE = {
      no_thorough_validation: ["No passing Thorough validation is recorded for this website.", :run_thorough],
      missing_discovery_proof: ["No successful Thorough run recorded the required fresh ResourceList discovery evidence.", :run_thorough],
      current_scope_unverified: ["The passing Thorough evidence does not cover the current event scope and configuration.", :run_thorough],
      incomplete_thorough_evidence: ["The recorded discovery proof was not accompanied by a complete Thorough comparison.", :run_thorough],
      discovery_configuration_changed: ["The ResourceList configuration changed since the last recorded discovery.", :run_thorough],
      no_discovery_lists: ["No event ResourceLists are configured.", :review_list_configuration],
      no_event_discovery: ["All event ResourceLists returned valid empty results. Confirm the calendar is expected to be empty.", :review_list_configuration],
      source_not_fetched: ["No successful source fetch is recorded.", :refetch_source],
      source_fetch_failed: ["The latest source fetch failed.", :refetch_source],
      source_fetch_stale: ["The last successful source fetch is stale.", :refetch_source],
      missing_statement_extraction: ["Source available; statement extraction required.", :refresh_statements],
      extraction_configuration_changed: ["The list or its extraction configuration changed after the statements were saved.", :refresh_statements],
      extraction_predates_source: ["List statements were last saved before the latest source fetch.", :refresh_statements],
      stale_list: ["The discovery statements are stale.", :refresh_statements],
      stale_or_unpaired_list: ["The required list statements have no verified paired extraction within 10 minutes.", :refresh_statements],
      extraction_failed: ["Extraction failed. Inspect the DSL result and refetch if the source content is the cause.", :inspect_extraction],
      invalid_or_empty_list: ["The URL and RDF URI arrays are malformed or unmatched.", :inspect_extraction],
      invalid_list: ["The URL and RDF URI arrays are malformed or unmatched.", :inspect_extraction],
      pagination_gap: ["An empty page precedes a populated page in the same pagination sequence. Review completeness.", :review_list_configuration],
      empty_list: ["Valid empty extraction: no events on this page.", nil],
      stale_extracted_discovery_class: ["The extracted RDF Class is older than its configuration.", :refresh_statements],
      unreviewed_extracted_discovery_class: ["The extracted RDF Class needs review before discovery can use it.", :inspect_extraction],
      unreviewed_discovery_list: ["The extracted list statements need review before reconciliation.", :inspect_extraction],
      manual_discovery_list_override: ["A manual override is holding a list statement.", :review_list_configuration],
      fixed_discovery_list_payload: ["A fixed DSL value cannot verify live discovery.", :review_list_configuration],
      ambiguous_list: ["A usable selected URL and RDF URI statement pair could not be determined.", :inspect_extraction],
      pending_reconciliation: ["New event URLs require reconciliation.", :reconcile_urls],
      listed_events_unpublishable: ["Listed events are missing required statements.", :refresh_listed_event_statements],
      discovery_complete: ["Discovery complete. No new webpages to create.", nil],
      other_class: ["This ResourceList is outside event discovery.", nil]
    }.freeze

    ACTIONS = {
      refetch_source: "Refetch source",
      refresh_statements: "Refresh statements",
      inspect_extraction: "Inspect the DSL result",
      reconcile_urls: "Reconcile discovered URLs",
      refresh_listed_event_statements: "Refresh the affected event statements",
      run_thorough: "Run Thorough validation",
      review_list_configuration: "Review ResourceList configuration"
    }.freeze

    def self.guidance(reason)
      return {} unless reason
      key = reason.to_sym
      message, action = GUIDANCE.fetch(key) { ["ResourceList configuration needs review (#{key.to_s.humanize}).", :review_list_configuration] }
      { reason: key, message: message, next_action: action }
    end

    def self.for_lists(lists, activity:)
      lists.map do |list|
        evidence = activity.fetch(list.fetch(:webpage_id))
        fetch = evidence.fetch(:fetch)
        extraction = evidence.fetch(:extraction)
        extraction_reason = (list[:extraction_reason] || list[:reason])&.to_sym
        extraction_reason = :extraction_configuration_changed if extraction_reason == :list_configuration_changed
        extraction_state, extraction_reason =
          if extraction[:latest_attempt_failed] || extraction_reason == :extraction_failed
            [:failed, :extraction_failed]
          elsif list[:status] == "other_class"
            [:not_applicable, nil]
          elsif extraction_reason == :pagination_gap
            [:verified, nil]
          elsif extraction_reason
            [extraction[:last_success_at] ? :unverified : :unknown, extraction_reason]
          elsif extraction[:last_success_at] && fetch[:last_success_at] && extraction[:last_success_at] < fetch[:last_success_at]
            [:older_than_source, :extraction_predates_source]
          else
            [:verified, nil]
          end

        missing = list[:new_count]
        reconciliation_state = if list[:status] != "event"
          :unverified
        elsif missing.to_i.positive?
          :pending
        else
          :complete
        end
        reconciliation_reason = { pending: :pending_reconciliation, complete: :discovery_complete }[reconciliation_state]
        reconciliation_reason = :empty_list if reconciliation_state == :complete && list[:status] == "event" && list[:count] == 0
        # Valid legacy list evidence is retained even when its source fetch was never recorded locally.
        reason = if list[:status] == "other_class"
          :other_class
        elsif fetch[:state].in?(%i[failed stale]) && (extraction_reason != :extraction_failed || extraction[:failed_primary_fetch])
          fetch[:state] == :failed ? :source_fetch_failed : :source_fetch_stale
        elsif list[:reason].to_s == "pagination_gap"
          :pagination_gap
        elsif fetch[:state] == :unknown && extraction[:saved_inputs].empty? &&
            extraction_reason.in?(%i[missing_statement_extraction stale_list stale_or_unpaired_list])
          :source_not_fetched
        else
          extraction_reason || reconciliation_reason
        end
        health = if list[:status] == "other_class"
          :not_applicable
        elsif fetch[:state] == :failed || extraction[:latest_attempt_failed] ||
            extraction_reason == :extraction_failed || list[:reason].to_s.in?(%w[invalid_list invalid_or_empty_list])
          :failed
        elsif list[:status] == "event" || list[:reason].to_s.in?(%w[stale_list pagination_gap])
          :healthy
        else
          :unknown
        end
        guidance = guidance(reason)
        guidance[:message] = "#{missing} new event #{missing == 1 ? 'URL requires' : 'URLs require'} reconciliation." if reason == :pending_reconciliation
        list.slice(:webpage_id, :website_id, :url, :warning, :status, :contents_digest).merge(
          health: health, fetch: fetch, extraction: extraction.merge(state: extraction_state, reason: extraction_reason),
          pagination: list[:pagination],
          reconciliation: { state: reconciliation_state, discovered: list[:discovered_count] || list[:count], already_known: list[:known_count],
            new_urls: missing, missing_urls: list[:missing_count], invalid_urls: list[:invalid_count] },
          **guidance
        )
      end
    end

    def self.validation(summary, inventory, list: nil)
      if summary.milestone == "migrated"
        state = :migrated
        warning = "Migration preserved. Review current ResourceList operations." if summary.changed ||
          inventory&.dig(:lists)&.any? { |list| list[:next_action].present? } ||
          inventory&.dig(:unpublishable_urls_count).to_i.positive?
      elsif summary.milestone == "ready"
        state = :qualified
      else
        state = :not_qualified
      end
      blocker = summary.milestone_reason
      current_proof = list && summary.discovery_proof&.fetch(list.fetch(:webpage_id).to_s, nil)
      lists = Array(inventory&.dig(:lists))
      blocking_list = list || lists.find { |item| item[:status] == "unverified" && item[:next_action].present? }
      reason = blocker
      if state == :not_qualified && (blocker.nil? || blocker == :missing_discovery_proof)
        reason = blocking_list[:reason] if blocking_list&.dig(:next_action)
        reason ||= :missing_discovery_proof if summary.latest_thorough
        reason ||= :no_thorough_validation if lists.any? { |item| item[:status] == "event" }
      end
      { state: state, covered: summary.covered, eligible: summary.eligible,
        last_pass: summary.latest_thorough || summary.last_pass, warning: warning,
        current_list_verified: current_proof && current_proof == list[:contents_digest], **guidance(reason) }
    end
  end
end
