# app/controllers/options_controller.rb
class OptionsController < ApplicationController
  TABS = { "monitoring" => "Monitoring", "transition" => "Transition", "trace" => "DSL trace",
    "connections" => "Connections" }.freeze
  INSPECTION_URLS = { console_inspection_url: "Console", wringer_inspection_url: "Wringer" }.freeze

  def index
    @tab = TABS.key?(params[:tab]) ? params[:tab] : "monitoring"
    case @tab
    when "monitoring"
      @monitoring_setting = MonitoringSetting.current
    when "transition"
      @production_preflight = Distillator::ProductionPreflight.call
      @staging_rollout_repair_preview = Distillator::StagingRolloutRepair.call if Distillator::TransitionRuntime.staging?
    end
  end

  def update_monitoring
    setting = MonitoringSetting.current
    if setting.update(params.require(:monitoring_setting).permit(:mailbox, :weekly_pulse_enabled))
      redirect_to options_path, notice: "Monitoring settings saved."
    else
      redirect_to options_path, alert: setting.errors.full_messages.to_sentence
    end
  end

  def repair_staging_rollout
    unless Distillator::TransitionRuntime.staging?
      redirect_to options_path(tab: "transition"), alert: "Staging rollout repair can only run on staging."
      return
    end

    result = Distillator::StagingRolloutRepair.call(apply: true, actor: "options", reason: "Options staging rollout repair")

    if result.success?
      notice =
        if result.invalid_count.zero?
          "Staging rollout repair found no invalid websites."
        else
          "Staging rollout repair moved #{result.repaired_count} websites to Shadow. #{result.unchanged_websites.count} unrepaired."
        end
      redirect_to options_path(tab: "transition"), notice: notice
    else
      redirect_to options_path(tab: "transition"), alert: "Staging rollout repair moved #{result.repaired_count} websites to Shadow. #{result.unchanged_websites.count} unrepaired. #{result.errors.join(', ')}"
    end
  end
  
  def wringer_reachability
    response.headers["Cache-Control"] = "no-store"
    render json: Distillator::WringerReachability.new.call
  end

  def update_connections
    values = params.permit(*INSPECTION_URLS.keys)
    urls = {}
    INSPECTION_URLS.each do |key, label|
      next unless values.key?(key)

      raw = values[key].to_s.strip
      url = OperatorInspectionUrl.normalize(raw)
      if raw.present? && (url.nil? || raw.bytesize > 1.kilobyte)
        redirect_to options_path(tab: "connections"), alert: "#{label} needs an HTTP or HTTPS base URL without credentials, a query, or a fragment."
        return
      end
      urls[key] = url
    end
    urls.each do |key, url|
      if url
        cookies.signed[key] = { value: url, expires: 30.days.from_now, httponly: true, secure: request.ssl?, same_site: :lax }
      else
        cookies.delete(key)
      end
    end
    redirect_to options_path(tab: "connections"), notice: "Inspection URLs saved for this browser."
  end

  def set_dsl_trace
    state = params[:state] == "true" ? "true" : "false"
    cookies[:dsl_trace] = { value: state, expires: 1.day.from_now }
    redirect_to options_path(tab: "trace"), notice: "DSL Trace #{state == 'true' ? 'enabled' : 'disabled'}"
  end

  def set_trace_visibility
    cookies[:trace_visibility] = {
      value: params[:state],
      expires: 1.day.from_now
    }

    redirect_back fallback_location: options_path(tab: "trace")
  end

  def set_trace_code_length
    cookies[:trace_code_display_length] = {
      value: params[:length],
      expires: 1.day.from_now
    }
    redirect_back fallback_location: options_path(tab: "trace")
  end

  def set_trace_output_length
    cookies[:trace_output_display_length] = {
      value: params[:length],
      expires: 1.day.from_now
    }
    redirect_back fallback_location: options_path(tab: "trace")
  end

  def set_trace_view_mode
    cookies[:trace_view_mode] = {
      value: params[:mode],
      expires: 1.day.from_now
    }

    redirect_back fallback_location: options_path(tab: "trace")
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

    redirect_back fallback_location: options_path(tab: "trace")
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
    redirect_to options_path(tab: "trace")
  end

end
