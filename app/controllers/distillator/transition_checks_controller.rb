module Distillator
  class TransitionChecksController < ApplicationController
    def create
      website = Website.find(params[:website_id])
      request = Distillator::TransitionRun.request!(website: website)
      if request.created?
        begin
          job = Distillator::TransitionCheckJob.perform_later(website.id, run_id: request.run.id)
          raise "Job enqueue was declined" unless job
        rescue StandardError => error
          Rails.logger.warn(event: "distillator.transition.enqueue_failed", run_id: request.run.id, error_class: error.class.name)
          request.run.fail!("Unable to queue the transition check. Check the worker connection and retry.")
          return redirect_to transition_check_return_path(website), alert: request.run.error_message
        end
      else
        return redirect_to transition_check_return_path(website), notice: "A transition check is already #{request.run.status}."
      end

      redirect_to transition_check_return_path(website), notice: "Transition batch check queued. The transition report will update when all phases finish."
    end

    private

    def transition_check_return_path(website)
      return_to = safe_return_to_param
      return return_to if return_to.present?

      distillator_shadow_report_site_path(website)
    end
  end
end
