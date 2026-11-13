module Distillator
  class TransitionChecksController < ApplicationController
    PHASE_LABELS = { "fetch_parity" => "Fetch", "statement_delta" => "Statements", "export_diff" => "Export" }.freeze

    def show
      @run = Distillator::TransitionRun.find(params[:id])
      @website = @run.website
      @report_path = distillator_shadow_report_site_path(@website, run_id: @run.id, anchor: "transition-report-summary")
      @run_status = run_status
      response.headers["Cache-Control"] = "no-store"
      respond_to do |format|
        format.html
        format.json { render json: @run_status }
      end
    end

    def create
      website = Website.find(params[:website_id])
      request = Distillator::TransitionRun.request!(website: website, options: requested_options)
      if request.created?
        begin
          job = Distillator::TransitionCheckJob.perform_later(website.id, run_id: request.run.id)
          raise "Job enqueue was declined" unless job
        rescue StandardError => error
          Rails.logger.warn(event: "distillator.transition.enqueue_failed", run_id: request.run.id, error_class: error.class.name)
          request.run.fail!("Unable to queue the transition check. Check the worker connection and retry.")
          flash.delete(:notice)
          return redirect_to distillator_transition_check_path(request.run), alert: request.run.error_message
        end
      else
        return redirect_to distillator_transition_check_path(request.run), notice: "A transition check is already #{request.run.status}."
      end

      redirect_to distillator_transition_check_path(request.run), notice: "Transition check ##{request.run.id} queued."
    rescue Distillator::TransitionRun::OptionsConflict => error
      flash.delete(:notice)
      redirect_to distillator_transition_check_path(website.latest_transition_run), alert: error.message
    rescue ArgumentError => error
      flash.delete(:notice)
      redirect_to transition_check_return_path(website), alert: error.message
    end

    private

    def run_status
      status = @run.status
      expired = status.in?(%w[queued running]) && @run.requested_at <= Time.current - Distillator::TransitionRun::LEASE
      status = "expired" if expired
      error = expired ? "This check expired. Retry to start a new run with the same options." : @run.error_message
      message = case status
                when "queued" then "Waiting for a worker. This page follows this run automatically."
                when "running" then "Checking extracted values. The completed report will open automatically."
                when "completed" then "Check completed. Opening its comparison report; completion does not mean parity passed."
                else error.presence || "The check did not finish. Retry with the same options or change the scope."
                end
      recorded = @run.transition_evidences.distinct.pluck(:check_kind)
      { run_id: @run.id, status: status, label: status.humanize, message: message,
        phases_recorded: PHASE_LABELS.filter_map { |kind, label| label if recorded.include?(kind) },
        check_options: @run.options.to_h, report_url: @report_path }
    end

    def requested_options
      raw = params[:check_options]
      return {} unless params.key?(:check_options)
      raise ArgumentError, "Check options must be an object" unless raw.is_a?(ActionController::Parameters)

      Distillator::TransitionCheckOptions.new(raw.to_unsafe_h).to_h
    end

    def transition_check_return_path(website)
      return_to = safe_return_to_param
      return return_to if return_to.present?

      distillator_shadow_report_site_path(website)
    end
  end
end
