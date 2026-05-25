module Distillator::ShadowReportsHelper
  def shadow_report_status_options
    [
      ["All statuses", ""],
      ["Ready", "ready"],
      ["Needs review", "review"],
      ["Blocked", "blocked"],
      ["Not checked", "not_checked"]
    ]
  end

  def shadow_report_safety_options
    [
      ["All safety states", ""],
      ["Safe", "safe"],
      ["Review", "review"],
      ["Unsafe", "unsafe"],
      ["Unknown", "unknown"]
    ]
  end

  def shadow_report_confidence_options
    [
      ["All confidence levels", ""],
      ["High", "high"],
      ["Medium", "medium"],
      ["Low", "low"],
      ["Not checked", "not_checked"]
    ]
  end

  def shadow_report_health_severity_options
    [
      ["All health severities", ""],
      ["ok", "ok"],
      ["low", "low"],
      ["medium", "medium"],
      ["high", "high"],
      ["unknown", "unknown"]
    ]
  end

  def shadow_report_cohort_options
    [
      ["All cohorts", ""],
      [Distillator::Cohorts::LavitrinePipeline.label, Distillator::Cohorts::LavitrinePipeline.key],
      ["Other", "other"]
    ]
  end

  def shadow_report_mode_options
    options = [
      ["All rollout modes", ""],
      ["Legacy", "legacy"],
      ["Shadow", "shadow"],
      ["Active", "active"]
    ]
    return options unless Distillator::TransitionRuntime.staging?

    options + [["Invalid on staging", Distillator::ShadowReportQuery::STAGING_INVALID_FILTER]]
  end

  def shadow_report_promotable_options
    [
      ["All promotable states", ""],
      ["Yes", "yes"],
      ["No", "no"]
    ]
  end

  def shadow_report_summary_cards(summary_counts, title_prefix: nil)
    counts = summary_counts.to_h.symbolize_keys
    prefix = title_prefix.present? ? "#{title_prefix} " : ""
    [
      shadow_report_summary_card("#{prefix}Total", counts[:total], "unknown", "Sites in this report."),
      shadow_report_summary_card("#{prefix}Ready", counts[:ready], "healthy", "Sites that can be activated."),
      shadow_report_summary_card("#{prefix}Needs review", counts[:review], "warning", "Sites that need operator review."),
      shadow_report_summary_card("#{prefix}Blocked", counts[:blocked], "failed", "Sites blocked from activation."),
      shadow_report_summary_card("#{prefix}Not checked", counts[:not_checked], "unknown", "Sites without enough checks yet.")
    ]
  end

  def shadow_report_action_links(row)
    safe_join(
      shadow_report_actions(row).map do |action|
        if action[:kind] == :button
          button_to(action.fetch(:label), action.fetch(:url), method: action.fetch(:method, :post), params: action.fetch(:params, {}), class: "website-transition-button")
        else
          link_to(action.fetch(:label), action.fetch(:url))
        end
      end,
      " | "
    )
  end

  def shadow_report_mode_label(row)
    row.mode_label
  end

  def shadow_report_cohort_label(row)
    row.cohort_label.presence || "Other"
  end

  def shadow_report_production_backend_label(row)
    row.production_backend_label
  end

  def shadow_report_status_label(row_or_status)
    return row_or_status.readiness_label if row_or_status.respond_to?(:readiness_label)

    status = row_or_status.respond_to?(:status) ? row_or_status.status : row_or_status

    case status.to_sym
    when :ready
      "Ready"
    when :review
      "Needs review"
    when :blocked
      "Blocked"
    else
      "Not checked"
    end
  end

  def shadow_report_check_label(value)
    case value.to_sym
    when :passed
      "Passed"
    when :checked
      "Passed"
    when :failed
      "Failed"
    when :not_evaluated
      "Not evaluated"
    when :blocked_by_fetch
      "Blocked by fetch"
    when :inconclusive
      "Inconclusive"
    when :stale
      "Stale"
    else
      "Missing"
    end
  end

  def shadow_report_severity_label(row)
    row.severity.to_s.humanize
  end

  def shadow_report_timestamp(value)
    value.present? ? value.to_s : "Not recorded"
  end

  def transition_dashboard_cards(counts)
    cards = [
      shadow_report_summary_card("Legacy sites", counts[:legacy_sites], "unknown", "Wringer remains the production path."),
      shadow_report_summary_card("Shadow sites", counts[:shadow_sites], "warning", "Wringer production with Condenser comparison."),
      shadow_report_summary_card("Active sites", counts[:active_sites], "healthy", "Condenser is the production path."),
      shadow_report_summary_card("Priority sites", counts[:priority_sites], "warning", "La Vitrine pipeline sites in scope."),
      shadow_report_summary_card("Blocked sites", counts[:blocked_sites], "failed", "Sites currently blocked from activation."),
      shadow_report_summary_card("Promotable sites", counts[:promotable_sites], "healthy", "Sites ready to activate.")
    ]
    return cards unless Distillator::TransitionRuntime.staging?

    cards + [
      shadow_report_summary_card("Invalid on staging", shadow_report_invalid_on_staging_count, "failed", "Sites using rollout modes that staging should not serve.")
    ]
  end

  def shadow_report_invalid_on_staging_count
    return 0 unless Distillator::TransitionRuntime.staging?

    Distillator::TransitionRuntime.staging_invalid_rollout_mode_scope.count
  end

  def shadow_report_staging_rollout_warning
    return unless Distillator::TransitionRuntime.staging?

    count = shadow_report_invalid_on_staging_count
    return if count.zero?

    "Staging requires every website to be Shadow or Active. #{count} websites are invalid on staging."
  end

  def transition_blocker_cards(counts)
    [
      shadow_report_summary_card("Failed fetch", counts[:failed_fetch], "failed", "Sites blocked by failed fetch checks."),
      shadow_report_summary_card("Statement check not yet recorded", counts[:missing_statement_evidence], "warning", "Sites still missing a recorded statement check."),
      shadow_report_summary_card("Missing export evidence", counts[:missing_export_evidence], "warning", "Sites still missing export evidence."),
      shadow_report_summary_card("Stale evidence", counts[:stale_evidence], "warning", "Sites that need evidence refreshed."),
      shadow_report_summary_card("Redirect/cache health review", counts[:redirect_cache_health_review], "warning", "Sites that need redirect or cache-health review.")
    ]
  end

  def shadow_report_transition_evidence_rows(detail)
    detail.transition_evidence_explanations.map do |explanation|
      shadow_report_transition_evidence_row(explanation, detail)
    end
  end

  def shadow_report_transition_evidence_status_label(status)
    case status.to_sym
    when :passed, :checked
      "passed"
    when :failed
      "failed"
    when :not_evaluated
      "not evaluated"
    when :blocked_by_fetch
      "blocked by fetch"
    when :inconclusive
      "inconclusive"
    when :stale
      "stale"
    else
      "missing"
    end
  end

  def shadow_report_transition_evidence_block(evidence)
    return content_tag(:p, "Not recorded") unless evidence.present?

    pieces = []
    pieces << "Status: #{evidence.status}"
    pieces << "Checked at: #{shadow_report_timestamp(evidence.checked_at)}"
    pieces << "Issue: #{evidence.primary_issue_key}" if evidence.primary_issue_key.present?
    pieces << "Statement delta: #{evidence.statement_delta}" if evidence.statement_delta.present?
    pieces << "Export diff status: #{evidence.export_diff_status}" if evidence.export_diff_status.present?
    content_tag(:p, pieces.join(" | "))
  end

  def shadow_report_check_icon(state)
    case state.to_sym
    when :passed
      "✓"
    when :failed
      "✗"
    when :not_evaluated, :blocked_by_fetch, :inconclusive
      "!"
    when :stale
      "!"
    else
      "?"
    end
  end

  def shadow_report_decision_label(decision)
    decision.fetch(:label)
  end

  def shadow_report_primary_blocker_heading(blocker)
    blocker ? "#{blocker.check} (selected from sampled URLs)" : "None"
  end

  def shadow_report_main_blocker_lines(detail)
    [
      "Failed layer: #{detail.root_cause[:failed_layer]}",
      "Reason: #{detail.root_cause[:concrete_reason]}",
      "Affected sampled URLs: #{detail.root_cause[:affected_url_count]}"
    ]
  end

  def shadow_report_checked_pages_summary(scope)
    publishable_count = scope[:publishable_event_page_count].to_i
    sampled_count = scope[:representative_webpage_count].to_i

    if publishable_count.positive?
      "#{sampled_count} of #{publishable_count} publishable event pages."
    else
      "#{sampled_count} representative webpages."
    end
  end

  def shadow_report_statement_failure_groups(detail)
    Array(detail.statement_failure_groups)
  end

  def shadow_report_primary_blocker_details(detail)
    blocker = detail.primary_blocker
    return [] unless blocker.present?
    return blocker.details unless blocker.key == "fetch_parity"

    cache_payload = shadow_report_cache_payload(detail)
    details = []
    details << "URL: #{detail.summary.cache&.normalized_url || detail.transition_evidence_by_kind['fetch_parity']&.url}" if detail.summary.cache.present? || detail.transition_evidence_by_kind["fetch_parity"]&.url.present?
    details << "Issue: #{detail.summary.issue_key}" if detail.summary.issue_key.present?
    details << "Health: #{detail.summary.health_summary}" if detail.summary.health_summary.present?
    details << "Fetch result: #{cache_fetch_response_summary(cache_payload)}" if cache_payload.present?
    details << "Storage decision: #{cache_storage_decision(cache_payload)}" if cache_payload.present? && cache_storage_decision(cache_payload).present?
    details << "Stored cache body: #{cache_stored_body_summary(cache_payload)}" if cache_payload.present?
    details << "Latest attempt: #{shadow_report_timestamp(detail.summary.latest_refresh)}"
    details << "Latest successful refresh: #{shadow_report_timestamp(detail.summary.latest_successful_refresh)}"
    details
  end

  def shadow_report_primary_blocker_links(detail)
    blocker = detail.primary_blocker
    return [] unless blocker.present?
    return shadow_report_explanation_links(blocker, detail.summary.website, detail: detail) unless blocker.key == "fetch_parity"

    shadow_report_fetch_blocker_links(detail)
  end

  def shadow_report_scope_lines(scope)
    lines = []
    publishable_count = scope[:publishable_event_page_count].to_i
    sampled_count = scope[:representative_webpage_count].to_i

    if publishable_count.positive?
      lines << "Checked #{sampled_count} of #{publishable_count} publishable event pages."
    else
      lines << "Checked #{sampled_count} representative webpages because no publishable event pages were available."
    end
    lines << "Publishable event pages: #{publishable_count}"
    lines << "Sampled count: #{sampled_count}"
    lines << "Sampling rule: #{scope[:selection_rule]}"
    lines << "Statements refreshed: #{scope[:statements_refreshed_count]}"
    lines << "Statements failed: #{scope[:statements_failed_count]}"
    lines << "Export compared: #{scope[:export_compared] ? 'yes' : 'no'}"
    lines << "Export basis: #{scope[:export_basis]}"
    lines
  end

  def shadow_report_scope_warning(scope)
    return unless scope[:sample_small]

    "This check used a limited sample of representative webpages."
  end

  def shadow_report_url_matrix_actions(row, website)
    links = []

    cache_inspection_links(row[:url], website: website).each do |link|
      label =
        case link[:label]
        when "Compare"
          "Compare Condenser vs Wringer"
        when "Open active cache"
          "Open active Wringer cache"
        when "Webpage record"
          "Open webpage record"
        else
          link[:label]
        end

      links << link_to(label, link[:url])
    end

    return "No diagnostic links recorded." if links.empty?

    safe_join(links, " | ")
  end

  def shadow_report_root_cause_lines(root_cause)
    [
      "Failed layer: #{root_cause[:failed_layer]}",
      "Concrete reason: #{root_cause[:concrete_reason]}",
      "Affected sampled URLs: #{root_cause[:affected_url_count]}",
      "Next operator action: #{root_cause[:next_operator_action]}"
    ]
  end

  def shadow_report_matrix_reason(row, key)
    value = row[key]
    return if value.blank? || value == "ok"

    value.to_s.humanize
  end

  def truncated_url_label(url, max: 80)
    text = url.to_s
    return text if text.length <= max

    "#{text.first(max - 1)}..."
  end

  def external_website_link(url, label: nil, max: 80)
    return ERB::Util.html_escape(url.to_s) if url.blank?

    display_label = label.presence || truncated_url_label(url, max: max)
    return ERB::Util.html_escape(display_label) unless url.to_s.start_with?("http://", "https://")

    link_to(display_label, url, target: "_blank", rel: "noopener")
  end

  def cache_inspection_links(url, website: nil)
    Distillator::InspectionLinks.call(
      url: url,
      website: website,
      payload: Distillator::CacheLinkResolver.call(url: url, website: website)
    )
  end

  def shadow_report_sampled_webpages(detail)
    detail.url_matrix.map do |row|
      links = cache_inspection_links(row[:url], website: detail.summary.website)
      {
        url: row[:url],
        label: external_website_link(row[:url]),
        result: [row[:condenser_fetch_result], row[:cache_comparison_result]].join(" / "),
        key_issue: [shadow_report_matrix_reason(row, :fetch_reason), shadow_report_matrix_reason(row, :cache_compare_reason)].compact.first,
        links: links,
        primary_blocker: detail.root_cause[:failed_layer].to_s.in?(%w[fetch legacy lookup cache compare]) &&
          shadow_report_matrix_row_matches_root_cause?(row, detail.root_cause)
      }
    end
  end

  def shadow_report_explanation_links(explanation, website, detail: nil)
    explanation.links.map do |link|
      path =
        case link[:target]
        when :statements
          statements_path(seedurl: website.seedurl)
        when :transition_report
          distillator_shadow_report_site_path(website)
        when :cache
          distillator_cache_index_path
        when :failed_cache_result
          shadow_report_failed_cache_result_path(detail)
        when :compare_cache
          shadow_report_compare_cache_path(detail)
        when :compare_statements
          shadow_report_compare_statements_path(detail)
        when :active_wringer_cache
          shadow_report_active_wringer_cache_path(detail)
        else
          website_path(website)
        end

      next if path.blank?

      link_to(link[:label], path)
    end.compact
  end

  def shadow_report_cache_diagnostic_links(row)
    links = []
    payload = row.cache_link_payload || {}
    cache = row.respond_to?(:cache) ? row.cache : nil

    if cache.present?
      links << link_to("Open failed cache result", distillator_cache_path(cache))
    elsif payload[:active_cache_url].present?
      links << link_to("Open active Wringer cache", payload[:active_cache_url])
    end

    Array(payload[:secondary_links]).each do |link|
      links << link_to(link[:label], link[:url]) if link[:label].present? && link[:url].present?
    end

    safe_join(links.uniq, " | ")
  end

  def shadow_report_safety_label(row)
    row.safety.to_s.humanize
  end

  def shadow_report_confidence_label(row)
    row.confidence.to_s.humanize
  end

  private

  def shadow_report_summary_card(title, count, tone, description)
    {
      title: title,
      count: count.to_i,
      tone: tone,
      description: description
    }
  end

  def shadow_report_actions(row)
    return_to = operator_return_to_params
    links = [
      { label: "Latest report", url: distillator_shadow_report_site_path(row.website) },
      { label: "Website", url: website_path(row.website) },
      {
        kind: :button,
        label: "Run batch check",
        url: distillator_transition_checks_path,
        method: :post,
        params: { website_id: row.website.id }.merge(return_to)
      }
    ]
    links << { label: "Inspect publishable event pages", url: webpages_path(seedurl: row.website.seedurl) }
    links << { label: "Open cache diagnostics", url: website_cache_diagnostics_path(row.website) }

    links.uniq { |link| [link[:label], link[:url]] }
  end

  def shadow_report_transition_evidence_row(explanation, detail)
    evidence = detail.transition_evidence_by_kind[explanation.key]

    {
      label: explanation.check,
      status: shadow_report_transition_evidence_status_label(explanation.state),
      checked_at: shadow_report_timestamp(evidence&.checked_at),
      url: evidence&.url.presence || "Not recorded",
      headline: explanation.headline,
      next_action: explanation.next_action,
      details: explanation.details,
      links: shadow_report_explanation_links(explanation, detail.summary.website, detail: detail)
    }
  end

  def shadow_report_sampled_explanation(detail, url)
    detail.transition_evidence_explanations.find do |explanation|
      Array(detail.transition_evidence_by_kind[explanation.key]&.details.to_h&.[]("representative_webpages") ||
        detail.transition_evidence_by_kind[explanation.key]&.details.to_h&.[](:representative_webpages)).include?(url)
    end || detail.primary_blocker
  end

  def shadow_report_sampled_result_label(explanation)
    return "Not checked" unless explanation.present?

    case explanation.severity
    when "blocker"
      "Failed"
    when "warning"
      "Review"
    else
      "Passed"
    end
  end

  def shadow_report_fetch_blocker_links(detail)
    links = []
    failed_cache_path = shadow_report_failed_cache_result_path(detail)
    compare_path = shadow_report_compare_cache_path(detail)
    compare_statements_path = shadow_report_compare_statements_path(detail)
    active_wringer_path = shadow_report_active_wringer_cache_path(detail)
    condenser_path = shadow_report_condenser_cache_path(detail)

    links << link_to("Open failed cache result", failed_cache_path) if failed_cache_path.present?
    links << link_to("Compare Condenser vs Wringer", compare_path) if compare_path.present?
    links << link_to("Compare extracted statements", compare_statements_path) if compare_statements_path.present?
    links << link_to("Open active Wringer cache", active_wringer_path) if active_wringer_path.present?
    links << link_to("Open Condenser cache", condenser_path) if condenser_path.present? && condenser_path != failed_cache_path
    links
  end

  def shadow_report_failed_cache_result_path(detail)
    cache = detail.summary.cache
    return distillator_cache_path(cache) if cache.present?

    url = detail.transition_evidence_by_kind["fetch_parity"]&.url
    return if url.blank?

    distillator_cache_index_path(term: url)
  end

  def shadow_report_compare_cache_path(detail)
    payload = detail.summary.cache_link_payload || {}
    compare_link = Array(payload[:secondary_links]).find { |link| link[:label] == "Compare Condenser vs Wringer" }
    compare_link&.fetch(:url, nil) || payload[:compare_url]
  end

  def shadow_report_compare_statements_path(detail)
    url = detail.transition_evidence_by_kind["fetch_parity"]&.url || detail.summary.cache&.normalized_url
    return if url.blank?

    compare_extracted_statements_path(url: url, website_id: detail.summary.website.id)
  end

  def shadow_report_active_wringer_cache_path(detail)
    payload = detail.summary.cache_link_payload || {}
    payload[:active_cache_url]
  end

  def shadow_report_condenser_cache_path(detail)
    payload = detail.summary.cache_link_payload || {}
    condenser_link = Array(payload[:secondary_links]).find { |link| link[:label] == "Open Condenser cache" }
    condenser_link&.fetch(:url, nil) || payload[:distillator_cache_url]
  end

  def shadow_report_cache_payload(detail)
    return unless detail.summary.cache.present?

    cache = detail.summary.cache
    {
      http_response_code: cache.respond_to?(:http_response_code) ? cache.http_response_code : nil,
      content_type: cache.signals.to_h["content_type"],
      signals: cache.signals.to_h,
      body_bytes: cache.respond_to?(:body_bytes) ? cache.body_bytes : nil
    }.with_indifferent_access
  end

  def condenser_cache_url_for(payload)
    condenser_link = Array(payload[:secondary_links]).find { |link| link[:label] == "Open Condenser cache" }
    condenser_link&.fetch(:url, nil) || payload[:distillator_cache_url]
  end

  def shadow_report_matrix_row_matches_root_cause?(row, root_cause)
    case root_cause[:failed_layer]
    when "fetch"
      row[:condenser_fetch_result] == "Failed"
    when "legacy lookup"
      row[:legacy_lookup_result] != "OK"
    when "cache compare"
      row[:cache_comparison_result].in?(%w[Failed Review Unknown Missing])
    else
      false
    end
  end
end
