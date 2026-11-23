module Distillator
  # Read only the completed run's recorded evidence, never current cache health.
  class TransitionFetchSummary
    Result = Struct.new(:selected, :attempted, :condenser_succeeded, :wringer_available,
      :paired, :compared, :fresh, :issues, :wringer_retries, keyword_init: true)

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
      fresh = fetch[:fetch_basis] == "fresh_both"
      shared_missing, other = rows.partition { |row| fresh && TransitionExclusionReview.shared_source_missing?(row) }
      issues = other.flat_map { |row| issues_for(row) } + shared_missing.map { |row| shared_source_issue(row) }
      Result.new(selected: selected.to_i, attempted: attempts, condenser_succeeded: native,
        wringer_available: legacy, paired: paired, compared: statements[:compared_webpage_count],
        fresh: fresh, issues: issues, wringer_retries: rows.filter_map { |row| wringer_retry(row) })
    end

    def self.wringer_retry(row)
      fetch = row[:legacy_fetch].to_h.with_indifferent_access
      attempts = Array(fetch[:attempts])
      return if attempts.length < 2 && fetch[:retry_stopped].blank?

      { url: row[:url], attempts: attempts, recovered: fetch[:recovered] == true, retry_stopped: fetch[:retry_stopped] }.compact
    end

    def self.shared_source_issue(row)
      condenser = row[:http_response_code]
      wringer = row.dig(:legacy_fetch, :upstream_http_code)
      { url: row[:url], backend: "Both backends", code: "shared_source_unavailable",
        reason: "The source URL returned HTTP #{condenser} to Condenser and HTTP #{wringer} to Wringer.",
        action: "Verify whether the source URL is retired or has moved before recording a reviewed exclusion.",
        condenser_http_code: condenser, wringer_http_code: wringer }
    end

    def self.issues_for(row)
      issues = []
      if row[:fetch_reason] == "transition_check_timeout_budget_exceeded"
        reason = row[:attempted_condenser_fetch] == false ? "Runtime budget reached before this URL was fetched." : "Runtime budget reached without a completed fetch result for this URL."
        return [{ url: row[:url], backend: "Transition check", reason: reason,
          code: row[:fetch_reason], action: "Rerun the check with a smaller sample or a longer runtime budget.", http_code: nil }]
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
        confirmed_challenge = row.dig(:condenser_fetch, :cloudflare, :cf_mitigated) == "challenge"
        challenge = confirmed_challenge || [row[:fetch_reason], reason].join(" ").match?(/captcha|cloudflare/i)
        issues << { url: row[:url], backend: "Condenser", reason: reason, http_code: code,
          code: challenge ? "challenge" : (row[:fetch_reason].presence || "fetch_failed"),
          kind: challenge ? "challenge" : "fetch_failure",
          summary: challenge ? "Content was rejected as a Cloudflare/CAPTCHA challenge." : reason,
          action: confirmed_challenge ? "Share the recorded Cloudflare request details with site IT before rerunning the check." : action_for(code, [row[:fetch_reason], reason].join(" ")) }
      end
      if row[:legacy_lookup_status].present? && row[:legacy_lookup_status] != "ok"
        metadata = row[:legacy_fetch].to_h.with_indifferent_access
        code = metadata[:upstream_http_code].presence || metadata[:response_http_code]
        reason = row[:legacy_lookup_error].presence || "Wringer snapshot unavailable: #{row[:legacy_lookup_status].to_s.humanize.downcase}."
        issues << { url: row[:url], backend: "Wringer", reason: reason, http_code: code,
          code: code.to_i >= 400 ? "http_#{code}" : "wringer_#{row[:legacy_lookup_status]}",
          action: row[:legacy_lookup_status] == "missing_config" ? "Configure the Wringer endpoint, then rerun the check." : action_for(code, reason) }
      end
      issues
    end

    def self.action_for(code, reason)
      return "Check whether this event URL is still valid, then rerun the check." if code.to_i.in?([404, 410])
      return "Inspect the recorded response to confirm whether it is a challenge page, then rerun the check." if reason.to_s.match?(/captcha|cloudflare/i)
      return "Resolve the rendering problem, then rerun the check." if reason.to_s.match?(/phantomjs|renderer/i)

      "Retry the transition check; both backends will fetch fresh results again."
    end
    private_class_method :issues_for, :shared_source_issue, :action_for, :wringer_retry
  end
end
