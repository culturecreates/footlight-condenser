# ApplicationController
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception, prepend: true
  before_action :authenticate, unless: -> { Rails.env.test? }
  before_action :set_sticky_seedurl
  helper_method :safe_relative_return_path?, :safe_return_to_param, :preserved_return_to_params

  private

  def authenticate
    return true if Rails.env.development?
    authenticate_or_request_with_http_basic do |username, password|
      username == Rails.application.credentials.basic_authentication[:username] && 
      password == Rails.application.credentials.basic_authentication[:password]
    end
  end

  def set_sticky_seedurl
    if params[:seedurl].blank?
      params[:seedurl] = cookies[:seedurl] if cookies[:seedurl].present?
    else
      cookies[:seedurl] = params[:seedurl] 
    end
  end

  def safe_relative_return_path?(value)
    candidate = value.to_s
    candidate.start_with?("/") && !candidate.start_with?("//")
  end

  def safe_return_to_param(value = params[:return_to])
    return_to = value.to_s
    return return_to if safe_relative_return_path?(return_to)

    nil
  end

  def preserved_return_to_params(path = request.fullpath)
    safe_relative_return_path?(path) ? { return_to: path } : {}
  end

end
