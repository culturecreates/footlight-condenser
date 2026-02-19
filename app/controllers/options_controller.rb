# app/controllers/options_controller.rb
class OptionsController < ApplicationController
  def index 
    # render the options form 
  end
  
  def wringer
    wringer_url = params[:target] == 'live' ? 'http://footlight-wringer.herokuapp.com' : 'http://localhost:3009'
    cookies[:wringer_url] = { value: wringer_url, expires: 1.day.from_now }
    redirect_to options_path, notice: "Wringer set to #{wringer_url}"
  end

  def set_dsl_trace
    state = params[:state] == "true" ? "true" : "false"
    cookies[:dsl_trace] = { value: state, expires: 1.day.from_now }
    redirect_to options_path, notice: "DSL Trace #{state == 'true' ? 'enabled' : 'disabled'}"
  end

  def update_trace_options
    cookies[:trace_code_display_length]     = params[:trace_code_display_length]     if params[:trace_code_display_length]
    cookies[:trace_code_tooltip_length]     = params[:trace_code_tooltip_length]     if params[:trace_code_tooltip_length]
    cookies[:trace_output_display_length]   = params[:trace_output_display_length]   if params[:trace_output_display_length]
    cookies[:trace_output_tooltip_length]   = params[:trace_output_tooltip_length]   if params[:trace_output_tooltip_length]
  end

  def update
    # Save trace length preferences to cookies

    cookies[:trace_code_display_length]   = params[:trace_code_display_length]   if params[:trace_code_display_length].present?
    cookies[:trace_code_tooltip_length]   = params[:trace_code_tooltip_length]   if params[:trace_code_tooltip_length].present?
    cookies[:trace_output_display_length] = params[:trace_output_display_length] if params[:trace_output_display_length].present?
    cookies[:trace_output_tooltip_length] = params[:trace_output_tooltip_length] if params[:trace_output_tooltip_length].present?

    flash[:notice] = "Trace options saved"
    redirect_to options_path
  end

end


