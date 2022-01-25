# ApplicationController
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception, prepend: true
  before_action :set_sticky_seedurl

  private

  def set_sticky_seedurl
    if params[:seedurl].blank?
      params[:seedurl] = cookies[:seedurl] if !cookies[:seedurl].blank?
    else
      cookies[:seedurl] = params[:seedurl] 
    end
  end

end
