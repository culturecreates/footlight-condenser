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

  def compute_warning_type(step)
    step = normalize_step(step)
    output = step_output(step)

    return :empty if output.is_a?(Array) && output.empty?

    probe = step[:probe].is_a?(Hash) ? step[:probe].with_indifferent_access : {}
    return :probe if probe.present? && !probe[:skipped]

    nil
  end

  def compute_step_status(step)
    step = normalize_step(step)
    return :error if step[:error].present?
    return :warning if compute_warning_type(step).present?

    :ok
  end

  def semantic_label(step)
    step = normalize_step(step)
    step_type = step[:type].to_s.strip
    normalized_type = step_type.downcase

    case normalized_type
    when "xpath", "css"
      "Extraction"
    when "ruby"
      "Filter"
    when "url"
      "Navigation"
    when "if_xpath"
      "Condition"
    when "json"
      "JSON parse"
    else
      return step_type.capitalize if step_type.present?

      "Unknown"
    end
  end

  # semantic(step)
  # Centralized semantic interpretation.
  # DO NOT read step[:semantic] directly in views or logic.
  def semantic(step)
    step = normalize_step(step)
    raw_semantic = step[:semantic]
    return raw_semantic.to_s if raw_semantic.present?

    semantic_label(step).to_s.downcase
  end

  def explain_step(step, previous_step = nil)
    step = normalize_step(step)
    output = step_output(step)
    label = semantic_label(step)

    return "Execution failed" if step[:error].present?
    return "No elements matched selector" if label == "Extraction" && output.blank?
    return "All items were filtered out" if label == "Filter" && output.blank?
    return "Navigated to new page" if label == "Navigation"

    nil
  end

  def suggest_fix(step, previous_step = nil)
    step = normalize_step(step)
    previous_step = normalize_step(previous_step)
    return nil if step.blank?

    semantic = semantic(step)
    previous_semantic = previous_step.present? ? semantic(previous_step) : nil
    output = step_output(step)
    previous_output = step_output(previous_step)
    output_blank = output.blank?
    probe = step[:probe].is_a?(Hash) ? step[:probe].with_indifferent_access : {}
    probe_status = probe.dig(:result, :status)

    if semantic == "extraction" && output_blank && probe_status == "ok"
      return "Try using contains(@class, '...') instead of exact match"
    end

    if semantic == "filter" && output_blank
      return "Check filter condition — it may be too restrictive"
    end

    if step[:error].present? && previous_step.present? && previous_output.blank?
      return "Add a guard clause before this step (e.g. return if $array.empty?)"
    end

    if previous_step.present? &&
       previous_semantic == "navigation" &&
       semantic == "extraction" &&
       output_blank
      return "Verify selector on target page — structure may differ after navigation"
    end

    nil
  end

  def trace_error_details(step)
    step = normalize_step(step)
    raw_error = step[:error]
    error_payload = raw_error.is_a?(Hash) ? raw_error.with_indifferent_access : {}.with_indifferent_access
    source = error_payload[:source].to_s.presence
    error_type = error_payload[:error_type].to_s.presence
    semantic = semantic_label(step)

    category =
      if source == "wringer" || %w[WringerFetchError WringerSkip WringerUnsupportedAction].include?(error_type)
        "fetch"
      elsif semantic == "Navigation"
        "navigation"
      elsif raw_error.present?
        "extraction"
      else
        "unknown"
      end

    label =
      case category
      when "fetch" then "Fetch error"
      when "navigation" then "Navigation issue"
      when "extraction" then "Extraction error"
      else "Pipeline issue"
      end

    {
      source: source || "dsl",
      error_type: error_type,
      category: category,
      label: label
    }
  end

  def interactive_probe_text(step)
    step = normalize_step(step)
    probe = step[:probe]
    return nil unless probe.present?

    probe = probe.with_indifferent_access if probe.is_a?(Hash)
    result = probe[:result].is_a?(Hash) ? probe[:result].with_indifferent_access : {}
    return nil unless result[:status].to_s == "ok" && result[:output].present?

    output_value = result[:output]
    output_value = output_value.first if output_value.is_a?(Array)
    output_preview = output_value.to_s
    output_preview = "#{output_preview[0, 60]}..." if output_preview.length > 60
    "Probe: page loaded (#{output_preview})"
  end

  def interactive_wringer_meta(step)
    step = normalize_step(step)
    wringer = step[:wringer].is_a?(Hash) ? step[:wringer].with_indifferent_access : {}
    return nil if wringer.blank?

    signals = wringer[:signals].is_a?(Hash) ? wringer[:signals].with_indifferent_access : {}
    error_type = wringer[:error_type].presence
    network_status = signals[:network_status].presence.to_s
    return nil if error_type.blank? && network_status.blank?
    return nil if error_type.blank? && network_status == "ok"

    network = error_type.presence || network_status
    content = signals[:content_type].presence || wringer[:content_type].presence || "HTML"

    "Network: #{network.to_s.upcase} • Content: #{content.to_s.upcase}"
  end

  def first_empty_step(steps)
    return nil unless steps.is_a?(Array)

    steps.each do |step|
      step = normalize_step(step)
      output = step_output(step)
      return step if output.is_a?(Array) && output.empty?
    end

    nil
  end

  def diagnosis_relationship_hint(diagnosis, statement_status, steps = nil)
    return nil unless diagnosis.present?

    pipeline = diagnosis[:status]
    pipeline = pipeline.to_sym if pipeline.respond_to?(:to_sym)
    content = statement_status.to_s

    if pipeline == :ok && content == "missing"
      if steps.present?
        step = first_empty_step(steps)
        if step
          return "No data extracted — first empty result at Step #{step[:step]} (#{semantic_label(step)})"
        end
      end

      return "No data extracted despite successful pipeline execution — selectors or mapping may be incorrect."
    end

    if pipeline == :ok && content == "problem"
      return "Data extracted but flagged as problematic — content validation or transformation may be incorrect."
    end

    if pipeline == :error && content == "missing"
      return "Content missing due to pipeline failure (fetch, navigation, or upstream issue)."
    end

    if pipeline == :warning && content == "ok"
      return "Pipeline encountered issues but produced usable data (may rely on fallback or cache)."
    end

    nil
  end

  private

  def normalize_step(step)
    return {}.with_indifferent_access unless step.respond_to?(:to_h)

    step.to_h.with_indifferent_access
  end

  def step_output(step)
    step = normalize_step(step)
    step.key?(:output_full) ? step[:output_full] : step[:output]
  end
end
