# ApplicationController
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception, prepend: true
  before_action :set_sticky_seedurl, :selectable_websites

  private

  def set_sticky_seedurl
    params[:seedurl] = cookies[:seedurl] if !cookies[:seedurl].blank? && params[:seedurl].blank?
  end

  def selectable_websites
    # used in nav bar
    @selectable_websites = Website.all
    @website =
      if params[:seedurl].present?
        Website.where(seedurl: params[:seedurl]).first
      else
        @selectable_websites.first
      end
  end
end
