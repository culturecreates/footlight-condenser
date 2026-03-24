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

  def set_trace_visibility
    cookies[:trace_visibility] = {
      value: params[:state],
      expires: 1.day.from_now
    }

    redirect_back fallback_location: root_path
  end

  def set_trace_code_length
    cookies[:trace_code_display_length] = {
      value: params[:length],
      expires: 1.day.from_now
    }
    redirect_back fallback_location: root_path
  end

  def set_trace_output_length
    cookies[:trace_output_display_length] = {
      value: params[:length],
      expires: 1.day.from_now
    }
    redirect_back fallback_location: root_path
  end

  def set_trace_view_mode
    cookies[:trace_view_mode] = {
      value: params[:mode],
      expires: 1.day.from_now
    }

    redirect_back fallback_location: root_path
  end

  def set_trace_preset
    case params[:preset]
    when "clean"
      cookies[:dsl_trace] = { value: "false", expires: 1.day.from_now }
      cookies[:trace_view_mode] = { value: "1", expires: 1.day.from_now }
      cookies[:trace_visibility] = { value: "hidden", expires: 1.day.from_now }
    when "debug"
      cookies[:dsl_trace] = { value: "true", expires: 1.day.from_now }
      cookies[:trace_view_mode] = { value: "5", expires: 1.day.from_now }
      cookies[:trace_visibility] = { value: "always", expires: 1.day.from_now }
    end

    redirect_back fallback_location: root_path
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
