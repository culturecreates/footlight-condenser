module Distillator
  class TransitionEvidenceExplanation
    CHECK_LABELS = {
      "fetch_parity" => "Fetch parity",
      "statement_delta" => "Statements",
      "export_diff" => "Export"
    }.freeze
    DEFAULT_SELECTION_RULE = "Event pages first, ordered by archive date".freeze

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
      case state
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
      return "Fresh Condenser evidence is missing for this comparison." if reason == "cache_compare_missing"
      return "Fresh Condenser evidence differs from Wringer in blocking fields." if reason == "cache_compare_blocking_regression"
      case state
      when :passed
        "Fetch parity passed."
      when :failed
        "Fetch/cache failed for the representative URL."
      when :stale
        "Fetch parity is stale."
      else
        "Fetch parity has not been recorded yet."
      end
    end

    def statement_headline
      return "No representative event webpages were available." if reason == "no_representative_webpages"
      return "Fetch failed before statements could be refreshed." if state == :not_evaluated || reason == "fetch_failed_before_statement_refresh"
      return "No selected statements were found for the representative webpages." if state == :inconclusive || reason == "no_selected_statements"
      return "Statement refresh failed for #{pluralize(failing_statement_count, 'statement')}." if reason == "statement_refresh_failed" && failing_statement_count.positive?
      return "Statement refresh found #{pluralize(failing_statement_count, 'failing statement')}." if state == :failed
      return "Statements check is stale." if state == :stale
      return "Statement check not yet recorded." if state == :missing

      "Statements check passed."
    end

    def export_headline
      return "Fetch failed before export could be compared." if state == :blocked_by_fetch || reason == "fetch_failed_before_export_comparison"
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
      details << "Attempted Condenser fetch: #{evidence&.attempted_condenser_fetch? ? 'yes' : 'no'}" if evidence.present?
      details << "Issue: #{evidence.primary_issue_key}" if evidence&.primary_issue_key.present?
      details << "Legacy source: #{details_hash['legacy_source']}" if details_hash["legacy_source"].present?
      details << "Condenser source: #{details_hash['condenser_source']}" if details_hash["condenser_source"].present?
      details << "Compare performed: #{details_hash["comparison_performed"] ? 'yes' : 'no'}" if details_hash.key?("comparison_performed")
      details << "Reason: #{reason.humanize}" if reason.present?
      details
    end

    def statement_details
      details = []
      representative_webpages.each do |url|
        details << "Webpage: #{url}"
      end

      failing_statements.each do |statement|
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
        state == :passed ? "No fetch action is needed right now." : "Fix the fetch/cache failure first, then rerun the transition check."
      when "statement_delta"
        if state == :passed
          "No statement refresh action is needed right now."
        elsif state == :not_evaluated || reason == "fetch_failed_before_statement_refresh"
          "Fix the fetch/cache failure first, then rerun the transition check."
        elsif state == :inconclusive || reason == "no_selected_statements"
          "Verify selected sources/statements for the sampled webpages."
        elsif reason == "no_representative_webpages"
          "Confirm this website has representative event webpages before activating."
        else
          "Open the statement trace and fix the source before activating."
        end
      when "export_diff"
        if state == :passed
          "No export action is needed right now."
        elsif state == :blocked_by_fetch || reason == "fetch_failed_before_export_comparison"
          "Fix the fetch/cache failure first, then rerun the transition check."
        elsif reason == "export_generation_failed"
          "Fix the export generation failure, then rerun the transition check."
        else
          "Review the export comparison and rerun the transition check before activating."
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

    def refresh_errors
      Array(details_hash["refresh_errors"] || details_hash[:refresh_errors]).map(&:to_s)
    end

    def failing_statement_count
      explicit_count = details_hash["statements_failed_count"] || details_hash[:statements_failed_count]
      return explicit_count.to_i if explicit_count.present?
      return failing_statements.count if failing_statements.any?

      evidence&.statement_delta.to_i
    end

    def rdf_added_count
      evidence&.rdf_added_count
    end

    def rdf_removed_count
      evidence&.rdf_removed_count
    end

    def pluralize(count, noun)
      amount = count.to_i
      return "0 #{noun}s" if amount.zero?
      return "1 #{noun}" if amount == 1

      "#{amount} #{noun}s"
    end
  end
end
