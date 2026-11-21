require "digest"

module Distillator
  class StatementParityCheck
    DIAGNOSTIC_BYTES = 1024
    Result = Struct.new(:status, :reason, :artifacts, :url_results, :critical_failures, :optional_failures,
      :comparison_count, :slowest_sources, keyword_init: true)

    def self.call(website:, webpages:, url_results:, refresh_helper:, comparator: Distillator::MigrationComparator,
      strict: false, stop_requested: nil, progress: nil, compact_evidence: false, snapshot_reader: nil)
      artifacts = []
      timings = {}
      comparison_count = 0
      inputs = url_results.each_with_object({}) { |row, by_url| by_url[row[:url]] ||= row }
      rows = webpages.each_with_index.map do |page, index|
        progress&.call(index, webpages.length)
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
        sources = Statements::RefreshWebpageStatementsService.sources_for_webpage(page,
          default_language: website.default_language).select(&:selected?)
        # A single HTML pair cannot establish parity for sources that require
        # different rendered/unrendered responses. Do not conflate these inputs.
        if sources.map { |source| source.render_js == true }.uniq.length > 1
          next { url: page.url, status: "inconclusive", reason: "mixed_fetch_profiles" }
        end
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
          artifact.merge(verdict: verdict, webpage_url: page.url, source: artifact[:property_label],
            core_field: critical, severity: MigrationComparator.shared_extraction_failure?(artifact) ? "unverified" : ((critical || strict) ? "blocker" : "warning"))
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
        unsupported = entries.any? do |entry|
          [entry[:legacy_error], entry[:condenser_error]].compact.any? do |error|
            error.to_h["error_type"].to_s.include?("FetchUnsupported")
          end
        end
        if interrupted
          { url: page.url, status: "inconclusive", reason: "transition_check_timeout_budget_exceeded" }
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
      progress&.call(webpages.length, webpages.length)
      critical, optional = artifacts.reject do |entry|
        entry[:verdict] == MigrationComparator::MATCH || MigrationComparator.shared_extraction_failure?(entry) ||
          [entry[:legacy_error], entry[:condenser_error]].compact.any? { |error| error.to_h["error_type"].to_s.include?("FetchUnsupported") }
      end
        .partition { |entry| entry[:severity] == "blocker" }
      state, reason = if rows.any? && rows.all? { |row| row[:status] == "blocked_by_fetch" }
        [:pending, "fetch_failed_before_statement_refresh"]
      elsif rows.any? { |row| row[:status] == "blocked_by_fetch" }
        [:pending, "partial_fetch_failed_before_statement_refresh"]
      elsif rows.any? { |row| row[:reason] == "transition_check_timeout_budget_exceeded" }
        [:pending, "transition_check_timeout_budget_exceeded"]
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
        critical_failures: critical, optional_failures: optional, comparison_count: comparison_count,
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

    private_class_method :accumulate_timing, :compact_artifact
  end
end
