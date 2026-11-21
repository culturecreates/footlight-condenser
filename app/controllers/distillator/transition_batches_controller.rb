module Distillator
  class TransitionBatchesController < ApplicationController
    def index
      @batches = TransitionBatch.order(id: :desc).paginate(page: params[:page], per_page: 25)
      @counts = SiteTransition.where(batch_id: @batches.map(&:id)).group(:batch_id, :status).count
        .each_with_object({}) { |((id, status), count), out| (out[id] ||= {})[status] = count }
      singles = @counts.select { |_, counts| counts.values.sum == 1 }.keys
      @single_items = SiteTransition.where(batch_id: singles).index_by(&:batch_id)
    end

    def create
      batch = TransitionBatch.request!(website_ids: params[:website_ids], request_key: params[:request_key], selection_context: params[:selection_context])
      item = batch.site_transitions.order(:position).first
      redirect_to(batch.site_transitions.count == 1 ? distillator_site_transition_path(item) : distillator_transition_batch_path(batch))
    rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      redirect_to websites_path, alert: error.message
    end

    def show
      @batch = TransitionBatch.find(params[:id])
      @items = @batch.site_transitions.includes(:website, :pre_run, :post_run).order(:position).to_a
      return redirect_to(distillator_site_transition_path(@items.first, format: request.format.json? ? :json : nil)) if @items.one?
      response.headers["Cache-Control"] = "no-store"
      respond_to do |format|
        format.html
        format.json { render json: { html: render_to_string(partial: "status", formats: [:html]), finished: @items.all?(&:terminal?) } }
      end
    end

    def update
      batch = TransitionBatch.find(params[:id])
      batch.stop_remaining!
      redirect_to distillator_transition_batch_path(batch), notice: "Queued sites stopped. The current site will finish validation or recovery."
    end
  end
end
