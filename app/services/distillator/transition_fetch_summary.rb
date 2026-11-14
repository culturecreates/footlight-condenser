module Distillator
  # Read only the completed run's recorded evidence, never current cache health.
  class TransitionFetchSummary
    Result = Struct.new(:selected, :attempted, :condenser_succeeded, :wringer_available,
      :paired, :compared, :fresh, :issues, keyword_init: true)

    def self.call(fetch_details:, statement_details:)
      fetch = fetch_details.to_h.with_indifferent_access
      statements = statement_details.to_h.with_indifferent_access
      rows = Array(fetch[:representative_url_results]).map { |row| row.to_h.with_indifferent_access }
      selected = fetch[:representative_webpage_count] || statements[:representative_webpage_count] || rows.length
      count = ->(field, &predicate) { rows.any? && rows.all? { |row| row[field].present? } ? rows.count(&predicate) : nil }
      native = count.call(:fetch_status) { |row| row[:fetch_status] == "passed" }
      legacy = count.call(:legacy_lookup_status) { |row| row[:legacy_lookup_status] == "ok" && !row[:compare_missing].to_h.with_indifferent_access[:legacy] }
      paired = if !native.nil? && !legacy.nil?
        rows.count { |row| row[:fetch_status] == "passed" && row[:legacy_lookup_status] == "ok" && !row[:compare_missing].to_h.values.any? }
      end
      attempts = fetch[:fetch_attempted_webpage_count]
      attempts ||= rows.count { |row| row[:attempted_condenser_fetch] } if rows.any? && rows.all? { |row| row.key?(:attempted_condenser_fetch) }
      issues = rows.flat_map { |row| issues_for(row) }
      Result.new(selected: selected.to_i, attempted: attempts, condenser_succeeded: native,
        wringer_available: legacy, paired: paired, compared: statements[:compared_webpage_count],
        fresh: fetch[:fetch_basis] == "fresh_both", issues: issues)
    end

    def self.issues_for(row)
      issues = []
      if row[:fetch_reason] == "transition_check_timeout_budget_exceeded"
        reason = row[:attempted_condenser_fetch] == false ? "Runtime budget reached before this URL was fetched." : "Runtime budget reached without a completed fetch result for this URL."
        return [{ url: row[:url], backend: "Transition check", reason: reason,
          action: "Rerun the check with a smaller sample or a longer runtime budget.", http_code: nil }]
      end
      if row[:fetch_status] == "failed"
        code = row[:http_response_code]
        reason = row[:condenser_error].presence
        reason ||= if code.to_i >= 400
          "The source returned HTTP #{code}."
        elsif row[:fetch_reason].to_s.in?(%w[failed cache_health_failed])
          "No usable fresh HTML was obtained. A detailed error was not recorded in this run."
        else
          row[:fetch_reason].to_s.humanize.presence || "Fetch failed; no further error was recorded."
        end
        issues << { url: row[:url], backend: "Condenser", reason: reason, http_code: code,
          action: action_for(code, row[:fetch_reason]) }
      end
      if row[:legacy_lookup_status].present? && row[:legacy_lookup_status] != "ok"
        metadata = row[:legacy_fetch].to_h.with_indifferent_access
        code = metadata[:upstream_http_code].presence || metadata[:response_http_code]
        reason = row[:legacy_lookup_error].presence || "Wringer snapshot unavailable: #{row[:legacy_lookup_status].to_s.humanize.downcase}."
        issues << { url: row[:url], backend: "Wringer", reason: reason, http_code: code,
          action: row[:legacy_lookup_status] == "missing_config" ? "Configure the Wringer endpoint, then rerun the check." : action_for(code, reason) }
      end
      issues
    end

    def self.action_for(code, reason)
      return "Check whether this event URL is still valid, then rerun the check." if code.to_i.in?([404, 410])
      return "Resolve the captcha or rendering problem, then rerun the check." if reason.to_s.match?(/captcha|phantomjs|renderer/i)

      "Retry the transition check; both backends will fetch fresh results again."
    end
    private_class_method :issues_for, :action_for
  end
end
