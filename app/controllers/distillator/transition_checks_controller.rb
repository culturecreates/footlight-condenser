module Distillator
  class TransitionChecksController < ApplicationController
    def create
      website = Website.find(params[:website_id])
      Distillator::TransitionCheckJob.perform_later(website.id)

      redirect_to transition_check_return_path(website), notice: "Transition check queued. The report will update as evidence is recorded."
    end

    private

    def transition_check_return_path(website)
      return_to = params[:return_to].to_s
      return return_to if safe_relative_return_path?(return_to)

      distillator_shadow_report_site_path(website)
    end

    def safe_relative_return_path?(value)
      value.start_with?("/") && !value.start_with?("//")
    end
  end
end
