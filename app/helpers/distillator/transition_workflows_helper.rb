module Distillator::TransitionWorkflowsHelper
  def workflow_phase_label(item)
    return item.status.humanize if item.terminal?
    return "Waiting for active-verification worker" if item.phase == "postcheck" && !item.phase_started_at
    label = { "queued" => "Waiting in group", "precheck" => "Pre-activation check", "postcheck" => "Active-path verification" }.fetch(item.phase)
    progress = item.current_run&.progress.to_h
    if progress["phase"].present?
      label += " · #{progress['phase'].humanize}"
      label += " · #{progress['completed']}/#{progress['total']} pages processed" if progress["total"]
    end
    label
  end

  def workflow_estimate(items)
    estimate = Distillator::TransitionTimeEstimate.remaining(items)
    return "Finished" if items.all?(&:terminal?)
    return "Taking longer than previous checks; remaining time is uncertain." if estimate[:overdue]
    return "Not enough previous timing data to estimate remaining work." if estimate[:seconds].zero?
    minutes = [estimate[:seconds] / 60.0, 1].max
    text = "Approximately #{[minutes * 0.7, 1].max.ceil}–#{(minutes * 1.6).ceil} minutes of work remaining, based on previous checks."
    text += " #{estimate[:unknown]} sites have no timing history." if estimate[:unknown].positive?
    text + " Queue waiting time is additional."
  end

  def workflow_elapsed(item)
    return "Not started" unless item.started_at
    seconds = ((item.completed_at || Time.current) - item.started_at).to_i
    "#{seconds / 60}m #{seconds % 60}s elapsed"
  end

  def workflow_state_badge(status)
    content_tag(:span, status.humanize, class: "transition-result transition-result--#{workflow_status_tone(status)}")
  end

  def workflow_status_tone(status)
    { "passed" => "passed", "attention" => "review", "cancelled" => "neutral", "recovery_failed" => "failed" }.fetch(status, "running")
  end

  def workflow_check_link(item, kind)
    run = item.public_send("#{kind}_run")
    data = item.phase_results.to_h[kind == :pre ? "precheck" : "postcheck"].to_h
    return item.initial_mode == "active" && kind == :pre ? "Already Active" : "Not run" unless run
    link_to "##{run.id} · #{data['state'].presence || run.status.humanize}",
      distillator_shadow_report_site_path(item.website_id, run_id: run.id)
  end
end
