module Distillator
  class TransitionBatchDiagnostics
    EXAMPLES_PER_KIND = 2
    MESSAGE_LIMIT = 800
    CHECK_PHASES = { "precheck" => :pre_run, "postcheck" => :post_run }.freeze
    CASCADED_REASONS = %w[
      fetch_failed_before_statement_refresh partial_fetch_failed_before_statement_refresh
      fetch_failed_before_export_comparison partial_fetch_failed_before_export_comparison
    ].freeze

    def initialize(batch:, items:)
      @batch = batch
      @items = items
      @redactor = PhantomjsRedaction.new("")
    end

    def call
      @redactor.call(
        schema_version: 1,
        batch_id: @batch.id,
        check_profile: @batch.check_profile,
        check_options: @batch.check_options,
        selection_context: @batch.selection_context,
        completed_at: @items.filter_map(&:completed_at).max&.iso8601,
        status_counts: @items.map(&:status).tally,
        sites: @items.map { |item| site_report(item) }
      )
    end

    private

    def site_report(item)
      runs = CHECK_PHASES.transform_values { |association| item.public_send(association) }.compact
      records = TransitionEvidence.where(transition_run_id: runs.values.map(&:id), check_kind: TransitionEvidence::REPORT_CHECK_KINDS)
        .latest_first.group_by(&:transition_run_id)
      issues = []
      checks = runs.map do |phase, run|
        evidence = records.fetch(run.id, []).uniq(&:check_kind).index_by(&:check_kind)
        issues.concat(run_issues(evidence, run).map { |issue| issue.merge(run_id: run.id, phase: phase) })
        item.phase_results.fetch(phase, {}).slice("state", "fetch", "statements", "export")
          .merge(phase: phase, run_id: run.id, status: run.status)
      end
      if item.status == "recovery_failed" || (item.status == "attention" && issues.empty?)
        issues << { kind: "workflow", code: item.status, message: message(item.reason) }
      end

      { website_id: item.website_id, name: item.website_name, seedurl: item.seedurl, workflow_id: item.id,
        status: item.status, initial_mode: item.initial_mode, final_mode: item.final_mode, final_backend: item.final_backend,
        reason: message(item.reason), checks: checks, issues: grouped_issues(issues) }.compact
    end

    def run_issues(evidence, run)
      issues = fetch_issues(evidence["fetch_parity"])
      issues.concat(statement_issues(evidence["statement_delta"]))
      issues.concat(export_issues(evidence["export_diff"]))
      if run.status == "failed"
        issues << { kind: "workflow", code: "run_failed", message: message(run.error_message) }
      end
      issues
    end

    def fetch_issues(record)
      return [] unless record

      details = record.details.to_h
      issues = TransitionFetchSummary.call(fetch_details: details, statement_details: {}).issues.map do |issue|
        { kind: "fetch", code: issue[:code], url: issue[:url], backend: issue[:backend],
          http_code: issue[:http_code], message: message(issue[:reason]) }
      end
      Array(details["representative_url_results"]).each do |row|
        status = row["comparison_status"]
        next unless status.in?(%w[failed review unknown missing]) && row["fetch_status"] != "failed"
        next if row["legacy_lookup_status"].present? && row["legacy_lookup_status"] != "ok"

        summary = row["compare_summary"].to_h
        fields = summary.values_at("blocking_regressions", "review_needed_diffs", "unknown_diffs", "operational_failures").flatten.compact.uniq
        issues << { kind: "cache_comparison", code: "cache_comparison_#{status}",
          url: row["url"], status: status, fields: fields.presence, message: message(summary["primary_reason"]) }
      end
      issues.presence || phase_issue(record, "fetch")
    end

    def statement_issues(record)
      return [] unless record

      details = record.details.to_h
      issues = Array(details["statement_artifacts"]).filter_map do |entry|
        verdict = entry["verdict"]
        next if verdict.blank? || verdict == MigrationComparator::MATCH

        errors = %w[legacy condenser].filter_map do |side|
          error = entry["#{side}_error"].to_h
          next if error.empty?

          { backend: side == "legacy" ? "Wringer input" : "Condenser input",
            error_type: error["error_type"], message: message(error["error"]) }.compact
        end
        code = if MigrationComparator.shared_extraction_failure?(entry)
          "shared_extraction_failure"
        elsif verdict == MigrationComparator::MISSING_STATEMENT && entry["core_field"] && errors.empty? &&
            %w[legacy condenser].all? { |side| entry.key?(side) && entry[side].nil? }
          "shared_missing_required_field"
        else
          errors.filter_map { |error| error[:error_type] }.uniq.join("+").presence || verdict.downcase
        end
        { kind: "statements", code: code, url: entry["webpage_url"], source_id: entry["source_id"],
          property: entry["property_label"], severity: entry["severity"], errors: errors.presence }
      end
      Array(details["representative_url_statement_results"]).each do |row|
        next unless row["status"] == "inconclusive" && row["reason"].present?

        issues << { kind: "statements", code: row["reason"], url: row["url"], status: row["status"] }
      end
      issues.presence || phase_issue(record, "statements")
    end

    def export_issues(record)
      return [] unless record

      details = record.details.to_h
      changes = { "export_literal_changed" => details["changed_literal_values"], "export_uri_changed" => details["changed_uri_objects"] }
      issues = changes.flat_map do |code, rows|
        Array(rows).map { |row| { kind: "export", code: code, subject: row["subject"], predicate: row["predicate"] } }
      end
      if record.rdf_added_count.to_i.positive? || record.rdf_removed_count.to_i.positive?
        issues << { kind: "export", code: "export_triples_changed", added_count: record.rdf_added_count, removed_count: record.rdf_removed_count }
      end
      issues.presence || phase_issue(record, "export")
    end

    def phase_issue(record, kind)
      reason = record.detail_reason
      return [] if reason.in?(CASCADED_REASONS) || record.status.in?(%w[checked accepted])

      details = record.details.to_h
      [{ kind: kind, code: reason.presence || "#{kind}_#{record.status}", status: record.status,
        error_type: details["error_class"], message: message(details["error_message"]) }]
    end

    def grouped_issues(issues)
      issues.group_by { |issue| issue.values_at(:kind, :code) }.map do |(kind, code), matches|
        examples = matches.map { |issue| issue.except(:kind, :code).compact }.uniq
        distinct_contexts = examples.uniq do |example|
          example.values_at(:phase, :backend, :source_id, :property, :fields, :predicate) +
            Array(example[:errors]).map { |error| error[:error_type] }
        end
        distinct_pages = examples.uniq { |example| example[:url] || example }
        { kind: kind, code: code, recorded_occurrences: matches.size,
          examples: (distinct_contexts | distinct_pages | examples).first(EXAMPLES_PER_KIND) }
      end
    end

    def message(value)
      @redactor.call(value.to_s).truncate(MESSAGE_LIMIT).presence
    end
  end
end
