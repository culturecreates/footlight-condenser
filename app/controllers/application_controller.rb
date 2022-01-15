# ApplicationController
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception, prepend: true
  before_action :set_sticky_seedurl, :selectable_websites

  private

  def set_sticky_seedurl
    if params[:seedurl].blank?
      params[:seedurl] = cookies[:seedurl] if !cookies[:seedurl].blank?
    else
      cookies[:seedurl] = params[:seedurl] 
    end
  end

  def selectable_websites
    # used in nav bar
    @selectable_websites = Website.all.order(:name)
    @website =
      if params[:seedurl].present?
        Website.where(seedurl: params[:seedurl]).first
      else
        @selectable_websites.first
      end
  end
end
