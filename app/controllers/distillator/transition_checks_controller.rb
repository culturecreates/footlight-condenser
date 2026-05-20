module Distillator
  class TransitionChecksController < ApplicationController
    def create
      website = Website.find(params[:website_id])
      Distillator::TransitionCheckRunner.call(website: website)

      redirect_to website_path(website), notice: "Transition check updated for #{website.seedurl}."
    end
  end
end
