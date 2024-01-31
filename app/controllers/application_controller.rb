# ApplicationController
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception, prepend: true
  before_action :authenticate, :set_sticky_seedurl

  private

  def authenticate
    authenticate_or_request_with_http_basic do |username, password|
      username == Rails.application.credentials.basic_authentication[:username] && 
      password == Rails.application.credentials.basic_authentication[:password]
    end
  end

  def set_sticky_seedurl
    if params[:seedurl].blank?
      params[:seedurl] = cookies[:seedurl] if !cookies[:seedurl].blank?
    else
      cookies[:seedurl] = params[:seedurl] 
    end
  end

end
