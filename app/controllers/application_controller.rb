class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception, prepend: true
  before_action :set_sticky_seedurl


  private
    def set_sticky_seedurl
      params[:seedurl] = cookies[:seedurl] if !cookies[:seedurl].blank? && params[:seedurl].blank?
    end

end
