module Distillator
  class TransitionRunProgress
    PHASE_EVIDENCE = { "fetch_parity" => "Fetch", "statement_delta" => "Statements", "export_diff" => "Export" }.freeze
    PHASE_NAMES = { "discovery" => "Refreshing ResourceLists", "selection" => "Selecting pages", "fetch" => "Fetch", "statements" => "Statements",
      "export" => "Export", "completed" => "Finalizing report" }.freeze

    def initialize(run, now: Time.current)
      @run = run
      @now = now
      @progress = run.progress.to_h
      @workflow = SiteTransition.active.where(pre_run_id: run.id).or(SiteTransition.active.where(post_run_id: run.id)).first
    end

    def call
      status = @run.status
      status = "expired" if status.in?(%w[queued running]) && @now >= lease_end && !@workflow
      evidence = @run.transition_evidences.distinct.pluck(:check_kind)
      active = status.in?(%w[queued running])
      { status: status, label: status.humanize, message: message(status), phase_message: phase_message(status, evidence),
        page_message: statement_page_message(evidence),
        waiting_message: active ? TransitionJobStatus.new(run: @run, workflow: @workflow, now: @now).message : nil,
        workflow_id: @workflow&.id,
        phases_recorded: PHASE_EVIDENCE.filter_map { |kind, label| label if evidence.include?(kind) } }
    end

    private

    def message(status)
      case status
      when "queued" then "The check has been queued."
      when "running" then "The completed report opens automatically."
      when "completed" then "Check completed. Opening its comparison report; completion does not mean parity passed."
      when "expired" then "This check expired. Retry to start a new run with the same options."
      else @run.error_message.presence || "The check did not finish. Retry with the same options or change the scope."
      end
    end

    def phase_message(status, evidence)
      phase = PHASE_NAMES[@progress["phase"]]
      if phase.nil? && status == "running"
        next_step = (PHASE_EVIDENCE.keys - evidence).first
        phase = PHASE_EVIDENCE[next_step] || PHASE_NAMES["completed"]
        return "Next phase: #{phase}."
      end
      return unless phase

      text = "#{status == 'running' ? 'Current' : 'Last'} phase: #{phase}"
      text += " · #{@progress['completed']}/#{@progress['total']} pages processed" if @progress["total"]
      text += " · updated #{local_time(Time.iso8601(@progress['updated_at']))}" if @progress["updated_at"]
      text
    end

    def statement_page_message(evidence)
      return unless @progress["phase"] == "statements" && evidence.include?("fetch_parity")

      index = Integer(@progress["completed"], exception: false)
      total = Integer(@progress["total"], exception: false)
      return unless index && total && index >= 0 && index < total

      # Statement comparison visits the same ordered page list recorded by Fetch.
      # Read just this URL, since Fetch evidence can be large.
      url = @run.transition_evidences.for_kind("fetch_parity").latest_first
        .where("details ->> 'representative_webpage_count' = ?", total.to_s)
        .pick(Arel.sql("details -> 'representative_webpages' ->> #{index}"))
      "Last page reached (#{index + 1}/#{total}): #{url}" if url.present?
    end

    def lease_end = @run.requested_at + TransitionRun::LEASE

    def local_time(time) = time.in_time_zone.strftime("%b %-d, %H:%M:%S %Z")
  end
end
