# app/controllers/options_controller.rb
class OptionsController < ApplicationController
  def index; end
  
  def wringer
    wringer_url = params[:target] == 'live' ? 'http://footlight-wringer.herokuapp.com' : 'http://localhost:3009'
    cookies[:wringer_url] = { value: wringer_url, expires: 1.day.from_now }
    redirect_to options_path, notice: "Wringer set to #{wringer_url}"
  end
end