module Distillator
  class StatementParityCheck
    Result = Struct.new(:status, :reason, :artifacts, :url_results, :critical_failures, :optional_failures, keyword_init: true)

    def self.call(website:, webpages:, url_results:, refresh_helper:, comparator: Distillator::MigrationComparator, strict: false, stop_requested: nil, progress: nil)
      artifacts = []
      rows = webpages.each_with_index.map do |page, index|
        progress&.call(index, webpages.length)
        if stop_requested&.call
          next { url: page.url, status: "inconclusive", reason: "transition_check_timeout_budget_exceeded" }
        end
        input = url_results.find { |row| row[:url] == page.url } || {}
        if input[:fetch_status] != "passed"
          next { url: page.url, status: "blocked_by_fetch", reason: input[:fetch_reason] || "paired_snapshot_missing" }
        end
        if input[:legacy_html].blank? || input[:condenser_html].blank?
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
          comparator.new(website: website, webpage: page, legacy_html: input[:legacy_html],
            condenser_html: input[:condenser_html], sources: sources, refresh_helper: refresh_helper,
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
            core_field: critical, severity: (critical || strict) ? "blocker" : "warning")
        end
        artifacts.concat(entries)
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
        elsif entries.any? { |entry| entry[:verdict] != MigrationComparator::MATCH }
          { url: page.url, status: "warning", reason: "optional_statement_parity_warning" }
        else
          { url: page.url, status: "passed", reason: "paired_statements_match" }
        end
      end
      progress&.call(webpages.length, webpages.length)
      critical, optional = artifacts.reject do |entry|
        entry[:verdict] == MigrationComparator::MATCH ||
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
        critical_failures: critical, optional_failures: optional)
    end
  end
end
