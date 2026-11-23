module Distillator
  class SiteTransitionsController < ApplicationController
    def show
      @item = SiteTransition.includes(:website, :pre_run, :post_run, :batch).find(params[:id])
      @website = @item.website
      response.headers["Cache-Control"] = "no-store"
      respond_to do |format|
        format.html
        format.json { render json: { html: render_to_string(partial: "status", formats: [:html]), finished: @item.terminal? } }
      end
    end

    def cancel
      item = SiteTransition.find(params[:id])
      path = params[:from] == "batch" ? distillator_transition_batch_path(item.batch) : distillator_site_transition_path(item)
      unless SiteTransition.cancellation_schema_ready?
        return redirect_to path, alert: SiteTransition::SCHEMA_NOT_READY
      end

      item.reload unless item.has_attribute?(:cancel_requested_at)
      unless item.request_cancellation!
        return redirect_to path, alert: "Only a running site transition can be cancelled."
      end

      dispatch_cancellation(item)
      redirect_to path, notice: "Cancellation requested for #{item.website_name}."
    end

    private

    def dispatch_cancellation(item)
      SiteTransitionJob.perform_later(item.id, phase: item.phase)
    rescue StandardError => error
      # The persisted request is still visible to the worker and reconciler.
      Rails.logger.warn(event: "distillator.site_transition.cancellation_enqueue_failed", id: item.id, error_class: error.class.name)
    end
  end
end
