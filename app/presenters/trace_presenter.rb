class TracePresenter
  DEFAULT_MODE = 3
  VALID_MODES = [1, 2, 3, 4, 5].freeze

  def initialize(trace)
    @trace = trace
  end

  def raw
    @trace
  end

  def steps
    if @trace.is_a?(Hash)
      raw = @trace.respond_to?(:to_h) ? @trace.to_h : @trace
      Array(raw[:steps] || raw["steps"])
    else
      @trace || []
    end
  end

  def mode(cookies)
    value = cookies[:trace_view_mode]&.to_i
    VALID_MODES.include?(value) ? value : DEFAULT_MODE
  end

  def visibility_setting(cookies)
    cookies[:trace_visibility].to_s.downcase.presence || "auto"
  end

  def visible?(cookies)
    case visibility_setting(cookies)
    when "always"
      true
    when "hidden"
      false
    when "auto"
      has_error?
    else
      has_error?
    end
  end

  def has_error?
    Array(steps).any? do |step|
      source = step.respond_to?(:to_h) ? step.to_h : {}
      next false unless source.is_a?(Hash)

      (source[:error] || source["error"] || source[:e] || source["e"]).present?
    end
  end
end
