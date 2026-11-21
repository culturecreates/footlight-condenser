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
  end
end
