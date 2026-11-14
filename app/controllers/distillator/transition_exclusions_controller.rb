module Distillator
  class TransitionExclusionsController < ApplicationController
    def create
      @website = Website.find(params[:website_id])
      run = @website.transition_runs.find(params[:source_run_id])
      TransitionExclusionReview.create!(website: @website, run: run, url: params[:url], reason: params[:reason])
      redirect_to distillator_shadow_report_site_path(@website), notice: "Reviewed exclusion recorded. Run a new check to compare the remaining eligible pages."
    rescue TransitionExclusionReview::InvalidReview, ActiveRecord::RecordInvalid => error
      redirect_to distillator_shadow_report_site_path(@website), alert: error.message
    rescue ActiveRecord::RecordNotUnique
      redirect_to distillator_shadow_report_site_path(@website), alert: "This URL is already excluded"
    end

    def update
      exclusion = TransitionExclusion.find(params[:id])
      @website = exclusion.website
      TransitionExclusionReview.restore!(exclusion: exclusion, reason: params[:reason])
      redirect_to distillator_shadow_report_site_path(@website), notice: "URL restored to transition scope. Run a new check before considering activation."
    rescue TransitionExclusionReview::InvalidReview, ActiveRecord::RecordInvalid => error
      redirect_to distillator_shadow_report_site_path(@website), alert: error.message
    end
  end
end
