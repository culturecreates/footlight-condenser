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
    [
      ["All rollout modes", ""],
      ["Legacy", "legacy"],
      ["Shadow", "shadow"],
      ["Active", "active"]
    ]
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
      shadow_report_actions(row).map { |action| link_to(action.fetch(:label), action.fetch(:url)) },
      " | "
    )
  end

  def shadow_report_mode_label(row)
    Distillator::RolloutCopy.label(row.website.distillator_mode)
  end

  def shadow_report_cohort_label(row)
    row.cohort_label.presence || "Other"
  end

  def shadow_report_production_backend_label(row)
    mode =
      if row.respond_to?(:website)
        row.website.distillator_mode
      elsif row.respond_to?(:distillator_mode)
        row.distillator_mode
      else
        :unknown
      end

    Distillator::RolloutCopy.active_backend_label(mode)
  end

  def shadow_report_status_label(row_or_status)
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
    when :failed
      "Failed"
    when :stale
      "Stale"
    else
      "Missing"
    end
  end

  def shadow_report_timestamp(value)
    value.present? ? value.to_s : "Not recorded"
  end

  def transition_dashboard_cards(counts)
    [
      shadow_report_summary_card("Legacy sites", counts[:legacy_sites], "unknown", "Wringer remains the production path."),
      shadow_report_summary_card("Shadow sites", counts[:shadow_sites], "warning", "Wringer production with Condenser comparison."),
      shadow_report_summary_card("Active sites", counts[:active_sites], "healthy", "Condenser is the production path."),
      shadow_report_summary_card("Priority sites", counts[:priority_sites], "warning", "La Vitrine pipeline sites in scope."),
      shadow_report_summary_card("Blocked sites", counts[:blocked_sites], "failed", "Sites currently blocked from activation."),
      shadow_report_summary_card("Promotable sites", counts[:promotable_sites], "healthy", "Sites ready to activate.")
    ]
  end

  def transition_blocker_cards(counts)
    [
      shadow_report_summary_card("Failed fetch", counts[:failed_fetch], "failed", "Sites blocked by failed fetch checks."),
      shadow_report_summary_card("Missing statement evidence", counts[:missing_statement_evidence], "warning", "Sites still missing statement evidence."),
      shadow_report_summary_card("Missing export evidence", counts[:missing_export_evidence], "warning", "Sites still missing export evidence."),
      shadow_report_summary_card("Stale evidence", counts[:stale_evidence], "warning", "Sites that need evidence refreshed."),
      shadow_report_summary_card("Redirect/cache health review", counts[:redirect_cache_health_review], "warning", "Sites that need redirect or cache-health review.")
    ]
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
    links = [
      { label: "Detail", url: distillator_shadow_report_site_path(row.website) },
      { label: "Website", url: website_path(row.website) },
      { label: "Options", url: options_path }
    ]
    links << { label: "Webpages", url: webpages_path(seedurl: row.website.seedurl) }
    links << { label: "Statements", url: statements_path(seedurl: row.website.seedurl) }

    payload = row.cache_link_payload || {}
    if payload[:active_cache_url].present?
      links << { label: payload[:label], url: payload[:active_cache_url] }
    end

    Array(payload[:secondary_links]).each do |link|
      links << link if link[:label].present? && link[:url].present?
    end

    links.uniq { |link| [link[:label], link[:url]] }
  end
end
