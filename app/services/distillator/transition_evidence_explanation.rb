module Distillator
  class TransitionEvidenceExplanation
    CHECK_LABELS = {
      "fetch_parity" => "Fetch parity",
      "statement_delta" => "Statements",
      "export_diff" => "Export"
    }.freeze
    DEFAULT_SELECTION_RULE = Distillator::TransitionCheck::SELECTION_RULE

    Result = Struct.new(
      :key,
      :check,
      :state,
      :severity,
      :headline,
      :details,
      :next_action,
      :links,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(check_kind:, evidence:, website:, state:)
      @check_kind = check_kind.to_s
      @evidence = evidence
      @website = website
      @state = state.to_sym
    end

    def call
      Result.new(
        key: check_kind,
        check: CHECK_LABELS.fetch(check_kind, check_kind.humanize),
        state: state.to_s,
        severity: severity,
        headline: headline,
        details: explanation_details,
        next_action: next_action,
        links: links
      )
    end

    private

    attr_reader :check_kind, :evidence, :website, :state

    def severity
      return "warning" if check_kind == "fetch_parity" && %w[legacy_lookup_missing_config legacy_lookup_unreachable legacy_lookup_body_omitted review_needed_difference].include?(reason)

      case state
      when :warning
        "warning"
      when :failed, :blocked_by_fetch, :not_evaluated
        "blocker"
      when :stale, :missing, :inconclusive
        website.lavitrine_pipeline? ? "blocker" : "warning"
      else
        "ok"
      end
    end

    def headline
      case check_kind
      when "fetch_parity"
        fetch_headline
      when "statement_delta"
        statement_headline
      when "export_diff"
        export_headline
      else
        "#{check_kind.humanize} is #{state}."
      end
    end

    def fetch_headline
      return "No representative event webpages were available." if reason == "no_representative_webpages"
      return "Latest Condenser attempt failed: empty body." if state == :failed && reason == "empty_body"
      return "Transition check reached its runtime budget before all sampled URLs were fetched." if reason == "transition_check_timeout_budget_exceeded"
      return "Captcha was detected while fetching one or more sampled URLs." if reason == "captcha_detected"
      return "Rendered fetch is unavailable because PHANTOMJS_API_KEY is missing." if reason == "phantomjs_api_key_missing"
      return "Rendered fetch is unavailable for one or more sampled URLs." if reason == "renderer_unavailable"
      return "Condenser fetch passed, but legacy Wringer lookup is missing staging configuration." if reason == "legacy_lookup_missing_config"
      return "Condenser fetch passed, but legacy Wringer lookup failed." if reason == "legacy_lookup_unreachable"
      return "Condenser fetch passed, but legacy Wringer body was omitted from the comparison endpoint." if reason == "legacy_lookup_body_omitted"
      return "Condenser and Wringer differ in fields that need manual review." if reason == "review_needed_difference"
      return "Condenser and Wringer differ only in metadata fields." if reason == "metadata_only_difference"
      return "Fresh Condenser evidence is missing for this comparison." if reason == "cache_compare_missing"
      return "Condenser and Wringer have a blocking parity mismatch." if reason == "cache_compare_blocking_regression"
      return "Condenser and Wringer comparison is still inconclusive." if reason == "cache_compare_unknown"
      case state
      when :passed
        "Fetch parity passed."
      when :failed
        failed_layer == "cache_compare" ? "Condenser and Wringer comparison failed." : "Condenser fetch/cache failed for one or more sampled URLs."
      when :stale
        "Fetch parity is stale."
      else
        "Fetch parity has not been recorded yet."
      end
    end

    def statement_headline
      return "No representative event webpages were available." if reason == "no_representative_webpages"
      return "Fetch failed before statements could be refreshed." if state == :not_evaluated || reason == "fetch_failed_before_statement_refresh"
      return "Some representative URLs could not be fetched, so statement coverage is incomplete." if reason == "partial_fetch_failed_before_statement_refresh"
      return "Transition check reached its runtime budget before statement coverage completed." if reason == "transition_check_timeout_budget_exceeded"
      return "No selected statements were found for the representative webpages." if state == :inconclusive || reason == "no_selected_statements"
      return "Legacy statement check failed before critical/optional classification was available." if legacy_generic_statement_failure?
      return "Critical statements passed; optional statement refresh warnings need review." if state == :warning || reason == "optional_statement_refresh_warning"
      return "Critical statement refresh failed for #{pluralize(critical_failing_statement_count, 'statement')}." if reason == "critical_statement_refresh_failed" && critical_failing_statement_count.positive?
      return "Critical statement refresh failed for #{pluralize(critical_failing_statement_count, 'statement')}; optional statement warnings also need review." if reason == "critical_and_optional_statement_refresh_failed" && critical_failing_statement_count.positive?
      return "Statement refresh found #{pluralize(failing_statement_count, 'failing statement')}." if state == :failed
      return "Statements check is stale." if state == :stale
      return "Statement check not yet recorded." if state == :missing

      "Statements check passed."
    end

    def export_headline
      return "Fetch failed before export could be compared." if state == :blocked_by_fetch || reason == "fetch_failed_before_export_comparison"
      return "Some representative URLs could not be fetched, so export coverage is incomplete." if reason == "partial_fetch_failed_before_export_comparison"
      return "Transition check reached its runtime budget before export coverage completed." if reason == "transition_check_timeout_budget_exceeded"
      return "Export could not be generated." if reason == "export_generation_failed"
      return "Export comparison is not available yet." if reason == "export_diff_not_available"
      return "No representative event webpages were available." if reason == "no_representative_webpages"
      return "Export comparison found #{pluralize(rdf_added_count, 'RDF statement')} added and #{pluralize(rdf_removed_count, 'RDF statement')} removed." if state == :failed
      return "Export comparison is stale." if state == :stale
      return "Export check not yet recorded." if state == :missing

      "Export comparison passed."
    end

    def explanation_details
      case check_kind
      when "statement_delta"
        statement_details
      when "export_diff"
        export_details
      else
        fetch_details
      end
    end

    def fetch_details
      details = []
      details << "URL: #{evidence.url}" if evidence&.url.present?
      details << "Failed layer: #{failed_layer.humanize}" if failed_layer.present?
      details << "Affected sampled URLs: #{affected_url_count}" if affected_url_count.positive?
      details << "Attempted Condenser fetch: #{evidence&.attempted_condenser_fetch? ? 'yes' : 'no'}" if evidence.present?
      if details_hash.key?("condenser_fetch_success")
        details << "Condenser fetch: #{details_hash['condenser_fetch_success'] ? 'passed' : 'failed'}"
      end
      details << "Issue: #{evidence.primary_issue_key}" if evidence&.primary_issue_key.present?
      details << "Legacy source: #{details_hash['legacy_source']}" if details_hash["legacy_source"].present?
      details << "Legacy lookup status: #{details_hash['legacy_lookup_status']}" if details_hash["legacy_lookup_status"].present?
      details << "Legacy lookup error: #{details_hash['legacy_lookup_error']}" if details_hash["legacy_lookup_error"].present?
      details << "Condenser source: #{details_hash['condenser_source']}" if details_hash["condenser_source"].present?
      details << "Comparison policy: #{details_hash['comparison_policy']}" if details_hash["comparison_policy"].present?
      details << "Compare performed: #{details_hash["comparison_performed"] ? 'yes' : 'no'}" if details_hash.key?("comparison_performed")
      details << "Reason: #{reason.humanize}" if reason.present?
      details
    end

    def statement_details
      details = []
      if legacy_generic_statement_failure?
        details << "Legacy statement failures recorded: #{failing_statement_count}" if failing_statement_count.positive?
        details << "Critical/optional split: not recorded"
      else
        details << "Critical statement failures: #{critical_failing_statement_count}" if critical_failing_statement_count.positive?
        details << "Optional statement warnings: #{optional_failing_statement_count}" if optional_failing_statement_count.positive?
      end
      representative_webpages.each do |url|
        details << "Webpage: #{url}"
      end

      critical_failing_statements.each do |statement|
        details << "Critical statement ID: #{statement[:id]}"
        details << "Critical source: #{statement[:source]}" if statement[:source].present?
        details << "Critical webpage: #{statement[:webpage_url]}" if statement[:webpage_url].present? && !representative_webpages.include?(statement[:webpage_url])
      end

      optional_failing_statements.each do |statement|
        details << "Statement ID: #{statement[:id]}"
        details << "Source: #{statement[:source]}" if statement[:source].present?
        details << "Webpage: #{statement[:webpage_url]}" if statement[:webpage_url].present? && !representative_webpages.include?(statement[:webpage_url])
      end

      refresh_errors.each do |error|
        details << "Reason: #{error}"
      end

      if details.empty? && evidence&.statement_delta.present?
        details << "Statement delta: #{evidence.statement_delta}"
      end
      details
    end

    def export_details
      details = []
      details << "URL: #{evidence.url}" if evidence&.url.present?
      details << "RDF added: #{rdf_added_count}" unless rdf_added_count.nil?
      details << "RDF removed: #{rdf_removed_count}" unless rdf_removed_count.nil?
      details << "Reason: #{reason.humanize}" if reason.present?
      details
    end

    def next_action
      case check_kind
      when "fetch_parity"
        return "Increase runtime coverage or rerun the transition batch check outside the web request budget." if reason == "transition_check_timeout_budget_exceeded"
        return "Resolve the captcha or use the direct inspection links for the affected URLs, then rerun the transition batch check." if reason == "captcha_detected"
        return "Configure PHANTOMJS_API_KEY or switch away from rendered fetch for the affected URLs, then rerun the transition batch check." if reason == "phantomjs_api_key_missing"
        return "Fix rendered fetch availability for the affected URLs, then rerun the transition batch check." if reason == "renderer_unavailable"
        return "Configure the Wringer endpoint for staging, then rerun the transition batch check." if reason == "legacy_lookup_missing_config"
        return "Fix the legacy Wringer endpoint, then rerun the transition batch check." if reason == "legacy_lookup_unreachable"
        return "Verify the legacy Wringer body endpoint or compare using the legacy inspection link." if reason == "legacy_lookup_body_omitted"
        return "Review the Condenser vs Wringer comparison for the affected URLs." if reason == "cache_compare_blocking_regression"
        return "Re-run the cache comparison and verify the affected URLs." if %w[cache_compare_missing cache_compare_unknown].include?(reason)

        state == :passed ? "No fetch action is needed right now." : "Fix the fetch/cache failure first, then rerun the transition batch check."
      when "statement_delta"
        if state == :passed
          "No statement refresh action is needed right now."
        elsif state == :not_evaluated || reason == "fetch_failed_before_statement_refresh"
          "Fix the fetch/cache failure first, then rerun the transition batch check."
        elsif reason == "transition_check_timeout_budget_exceeded"
          "Rerun the transition batch check with enough runtime budget to finish statement coverage."
        elsif reason == "partial_fetch_failed_before_statement_refresh"
          "Fetch the missing representative URLs, then rerun the transition batch check to complete statement coverage."
        elsif state == :inconclusive || reason == "no_selected_statements"
          "Verify selected sources/statements for the sampled webpages."
        elsif legacy_generic_statement_failure?
          "Rerun the transition batch check to record current statement evidence with critical/optional classification."
        elsif state == :warning || reason == "optional_statement_refresh_warning"
          "Review the optional statement refresh warnings before activating."
        elsif reason == "no_representative_webpages"
          "Confirm this website has representative event webpages before activating."
        else
          "Open the statement trace and fix the source before activating."
        end
      when "export_diff"
        if state == :passed
          "No export action is needed right now."
        elsif state == :blocked_by_fetch || reason == "fetch_failed_before_export_comparison"
          "Fix the fetch/cache failure first, then rerun the transition batch check."
        elsif reason == "transition_check_timeout_budget_exceeded"
          "Rerun the transition batch check with enough runtime budget to finish export coverage."
        elsif reason == "partial_fetch_failed_before_export_comparison"
          "Fetch the missing representative URLs, then rerun the transition batch check to complete export coverage."
        elsif reason == "export_generation_failed"
          "Fix the export generation failure, then rerun the transition batch check."
        else
          "Review the export comparison and rerun the transition batch check before activating."
        end
      else
        "Review this check before activating."
      end
    end

    def links
      case check_kind
      when "statement_delta"
        [{ label: "Statements", target: :statements }]
      when "export_diff"
        [{ label: "Transition report", target: :transition_report }]
      else
        [
          { label: "Open failed cache result", target: :failed_cache_result },
          { label: "Compare Condenser vs Wringer", target: :compare_cache },
          { label: "Compare extracted statements", target: :compare_statements },
          { label: "Open active Wringer cache", target: :active_wringer_cache }
        ]
      end
    end

    def details_hash
      @details_hash ||= evidence&.details.to_h || {}
    end

    def reason
      details_hash["reason"] || details_hash[:reason]
    end

    def representative_webpages
      Array(details_hash["representative_webpages"] || details_hash[:representative_webpages]).compact
    end

    def count_representative_webpages
      details_hash["representative_webpage_count"] || details_hash[:representative_webpage_count] || representative_webpages.count
    end

    def failing_statements
      Array(details_hash["failing_statements"] || details_hash[:failing_statements]).map do |entry|
        entry.respond_to?(:to_h) ? entry.to_h.symbolize_keys : {}
      end
    end

    def critical_failing_statements
      Array(details_hash["critical_failing_statements"] || details_hash[:critical_failing_statements]).map do |entry|
        entry.respond_to?(:to_h) ? entry.to_h.symbolize_keys : {}
      end
    end

    def optional_failing_statements
      explicit = Array(details_hash["optional_failing_statements"] || details_hash[:optional_failing_statements]).map do |entry|
        entry.respond_to?(:to_h) ? entry.to_h.symbolize_keys : {}
      end
      return explicit if explicit.any?

      failing_statements.reject { |entry| entry[:severity].to_s == "blocker" }
    end

    def refresh_errors
      Array(details_hash["refresh_errors"] || details_hash[:refresh_errors]).map(&:to_s)
    end

    def failing_statement_count
      explicit_count = details_hash["statements_failed_count"] || details_hash[:statements_failed_count]
      return explicit_count.to_i if explicit_count.present?
      return failing_statements.count if failing_statements.any?

      evidence&.statement_delta.to_i
    end

    def critical_failing_statement_count
      explicit_count = details_hash["critical_statements_failed_count"] || details_hash[:critical_statements_failed_count]
      return explicit_count.to_i if explicit_count.present?
      return critical_failing_statements.count if critical_failing_statements.any?

      evidence&.statement_delta.to_i
    end

    def optional_failing_statement_count
      explicit_count = details_hash["optional_statements_failed_count"] || details_hash[:optional_statements_failed_count]
      return explicit_count.to_i if explicit_count.present?

      optional_failing_statements.count
    end

    def rdf_added_count
      evidence&.rdf_added_count
    end

    def rdf_removed_count
      evidence&.rdf_removed_count
    end

    def failed_layer
      details_hash["failed_layer"] || details_hash[:failed_layer]
    end

    def affected_url_count
      (details_hash["affected_url_count"] || details_hash[:affected_url_count] || 0).to_i
    end

    def pluralize(count, noun)
      amount = count.to_i
      return "0 #{noun}s" if amount.zero?
      return "1 #{noun}" if amount == 1

      "#{amount} #{noun}s"
    end

    def legacy_generic_statement_failure?
      return false unless state == :failed && failing_statement_count.positive?

      !statement_failure_split_recorded?
    end

    def statement_failure_split_recorded?
      details_hash.key?("critical_statements_failed_count") ||
        details_hash.key?(:critical_statements_failed_count) ||
        details_hash.key?("optional_statements_failed_count") ||
        details_hash.key?(:optional_statements_failed_count)
    end
  end
end
