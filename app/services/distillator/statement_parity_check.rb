require "digest"

module Distillator
  class StatementParityCheck
    DIAGNOSTIC_BYTES = 1024
    Result = Struct.new(:status, :reason, :artifacts, :url_results, :critical_failures, :optional_failures,
      :comparison_count, :slowest_sources, :timings, keyword_init: true)

    def self.call(website:, webpages:, url_results:, refresh_helper:, comparator: Distillator::MigrationComparator,
      strict: false, stop_requested: nil, progress: nil, compact_evidence: false, snapshot_reader: nil, source_lookup: nil)
      source_lookup ||= ->(page) do
        Statements::RefreshWebpageStatementsService.sources_for_webpage(page, default_language: website.default_language).select(&:selected?)
      end
      artifacts = []
      timings = {}
      comparison_count = 0
      inputs = url_results.each_with_object({}) { |row, by_url| by_url[row[:url]] ||= row }
      rows = webpages.each_with_index.map do |page, index|
        progress&.call(index, webpages.length, timings)
        if stop_requested&.call
          next { url: page.url, status: "inconclusive", reason: "transition_check_timeout_budget_exceeded" }
        end
        input = inputs.fetch(page.url, {})
        if input[:fetch_status] != "passed"
          next { url: page.url, status: "blocked_by_fetch", reason: input[:fetch_reason] || "paired_snapshot_missing" }
        end
        legacy, condenser = snapshot_reader ? snapshot_reader.call(input) : input.values_at(:legacy_html, :condenser_html)
        if legacy.blank? || condenser.blank?
          next { url: page.url, status: "inconclusive", reason: "paired_snapshot_missing" }
        end
        sources = source_lookup.call(page)
        interrupted = false
        comparison = begin
          comparator.new(website: website, webpage: page, legacy_html: legacy,
            condenser_html: condenser, sources: sources, refresh_helper: refresh_helper,
            stop_requested: stop_requested).compare_statements
        rescue MigrationComparator::BudgetExceeded => error
          interrupted = true
          MigrationComparator::StatementComparison.new(artifacts: Array(error.artifacts))
        end
        entries = comparison.artifacts.map do |artifact|
          critical = page.rdfs_class.name == "Event" && Webpage.publishable_required_property_labels.include?(artifact[:property_label])
          verdict = if critical && artifact[:verdict] == MigrationComparator::MATCH && artifact[:condenser].nil?
            MigrationComparator::MISSING_STATEMENT
          else
            artifact[:verdict]
          end
          unverified = MigrationComparator.shared_extraction_failure?(artifact) || MigrationComparator.reconciliation_failure?(artifact)
          artifact.merge(verdict: verdict, webpage_url: page.url, source: artifact[:property_label],
            core_field: critical, severity: unverified ? "unverified" : ((critical || strict) ? "blocker" : "warning"))
        end
        comparison_count += entries.length
        entries.each do |entry|
          if compact_evidence
            accumulate_timing(timings, entry)
            artifacts << compact_artifact(entry) if entry[:verdict] != MigrationComparator::MATCH
          else
            artifacts << entry
          end
        end
        required = page.rdfs_class.name == "Event" ? Webpage.publishable_required_property_labels : []
        unsupported = entries.any? { |entry| unsupported_fetch?(entry) }
        if interrupted
          { url: page.url, status: "inconclusive", reason: "transition_check_timeout_budget_exceeded" }
        elsif entries.any? { |entry| MigrationComparator.reconciliation_failure?(entry) }
          { url: page.url, status: "inconclusive", reason: "reconciliation_inconclusive" }
        elsif entries.empty? || (required - entries.map { |entry| entry[:property_label] }).any? || unsupported
          { url: page.url, status: "inconclusive", reason: "paired_extraction_inconclusive" }
        elsif entries.any? { |entry| entry[:severity] == "blocker" && entry[:verdict] != MigrationComparator::MATCH }
          { url: page.url, status: "failed", reason: strict ? "strict_statement_parity_failed" : "critical_statement_parity_failed" }
        elsif entries.any? { |entry| MigrationComparator.shared_extraction_failure?(entry) }
          { url: page.url, status: "unverified", reason: "shared_extraction_failure" }
        elsif entries.any? { |entry| entry[:verdict] != MigrationComparator::MATCH }
          { url: page.url, status: "warning", reason: "optional_statement_parity_warning" }
        else
          { url: page.url, status: "passed", reason: "paired_statements_match" }
        end
      end
      progress&.call(webpages.length, webpages.length, timings)
      summarize(rows: rows, artifacts: artifacts, comparison_count: comparison_count, timings: timings, strict: strict)
    end

    def self.summarize(rows:, artifacts:, comparison_count:, timings:, strict:)
      critical, optional = artifacts.reject do |entry|
        entry[:verdict] == MigrationComparator::MATCH || MigrationComparator.shared_extraction_failure?(entry) ||
          unsupported_fetch?(entry) || MigrationComparator.reconciliation_failure?(entry)
      end
        .partition { |entry| entry[:severity] == "blocker" }
      state, reason = if rows.any? && rows.all? { |row| row[:status] == "blocked_by_fetch" }
        [:pending, "fetch_failed_before_statement_refresh"]
      elsif rows.any? { |row| row[:status] == "blocked_by_fetch" }
        [:pending, "partial_fetch_failed_before_statement_refresh"]
      elsif rows.any? { |row| row[:reason] == "transition_check_timeout_budget_exceeded" }
        [:pending, "transition_check_timeout_budget_exceeded"]
      elsif rows.any? { |row| row[:reason] == "reconciliation_inconclusive" }
        [:pending, "reconciliation_inconclusive"]
      elsif rows.empty? || rows.any? { |row| row[:status] == "inconclusive" }
        [:pending, "paired_extraction_inconclusive"]
      elsif rows.any? { |row| row[:status] == "unverified" }
        [:pending, "shared_extraction_failure"]
      elsif rows.any? { |row| row[:status] == "failed" }
        [:failed, "critical_statement_parity_failed"]
      elsif rows.any? { |row| row[:status] == "warning" }
        [:warning, "optional_statement_parity_warning"]
      else
        [:checked, "paired_statements_match"]
      end
      # A known critical failure cannot be hidden by incomplete coverage elsewhere.
      state, reason = :failed, (strict ? "strict_statement_parity_failed" : "critical_statement_parity_failed") if critical.any?
      Result.new(status: state, reason: reason, artifacts: artifacts, url_results: rows,
        critical_failures: critical, optional_failures: optional, comparison_count: comparison_count, timings: timings,
        slowest_sources: timings.values.sort_by { |row| -(row[:extraction_ms] + row[:formatting_ms]) }.first(10).map do |row|
          row.merge(extraction_ms: row[:extraction_ms].round(2), formatting_ms: row[:formatting_ms].round(2))
        end)
    end

    def self.accumulate_timing(timings, entry)
      row = timings[entry[:source_id]] ||= { source_id: entry[:source_id], field: entry[:property_label], executions: 0,
        extraction_ms: 0.0, formatting_ms: 0.0 }
      entry[:timing].to_h.each_value do |side|
        next unless side

        row[:executions] += 1
        row[:extraction_ms] += side[:extraction_ms].to_f
        row[:formatting_ms] += side[:formatting_ms].to_f
      end
    end

    def self.compact_artifact(entry)
      compact = entry.except(:timing)
      %i[legacy condenser].each do |side|
        value = entry[side]
        encoded = value.to_json
        if encoded.bytesize > DIAGNOSTIC_BYTES
          compact[side] = { preview: encoded.byteslice(0, DIAGNOSTIC_BYTES).scrub, sha256: Digest::SHA256.hexdigest(encoded),
            json_bytes: encoded.bytesize }
        end
        error_key = :"#{side}_error"
        error = entry[error_key]
        message = error&.[]("error")
        if message.is_a?(String) && message.bytesize > DIAGNOSTIC_BYTES
          compact[error_key] = error.merge("error" => "#{message.byteslice(0, DIAGNOSTIC_BYTES).scrub}… (SHA-256 #{Digest::SHA256.hexdigest(message)})")
        end
      end
      compact
    end

    def self.unsupported_fetch?(entry)
      lookup_error_types(entry).any? { |type| type.include?("FetchUnsupported") }
    end

    def self.lookup_error_types(entry)
      entry.values_at(:legacy_error, :condenser_error).compact.map { |error| error.to_h["error_type"].to_s }
    end

    private_class_method :accumulate_timing, :compact_artifact, :unsupported_fetch?, :lookup_error_types
  end
end
