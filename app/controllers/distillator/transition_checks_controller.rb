module Distillator
  class TransitionChecksController < ApplicationController
    def create
      website = Website.find(params[:website_id])
      website.request_transition_batch_check!
      Distillator::TransitionCheckJob.perform_later(website.id)

      redirect_to transition_check_return_path(website), notice: "Transition batch check queued. The latest transition report will update as evidence is recorded."
    end

    private

    def transition_check_return_path(website)
      return_to = safe_return_to_param
      return return_to if return_to.present?

      distillator_shadow_report_site_path(website)
    end
  end
end
