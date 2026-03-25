module Dsl
  class PipelineDiagnosis
    def initialize(metrics:, wringer: {}, steps: nil)
      @metrics = normalize_hash(metrics)
      @wringer = normalize_hash(wringer)
      wringer_signals = normalize_hash(@wringer[:signals])
      wringer_hints = Array(@wringer[:hints]).map(&:to_s)
      @wringer_signals = wringer_signals
      @wringer_hints = wringer_hints
      @steps = normalize_steps(steps)
    end

    def result
      # Rule priority (highest to lowest):
      # 1) pipeline execution error
      # 2) Wringer/fetch-layer failure
      # 3) data loss
      # 4) suspicious navigation
      # 5) extraction failure
      # 6) healthy fallback
      #
      # Wringer failures intentionally override navigation/extraction symptoms because
      # upstream fetch instability can manifest as downstream extraction emptiness.
      return error_diagnosis if @metrics[:error_present]
      return wringer_diagnosis if wringer_failure?
      return data_loss_diagnosis if @metrics[:data_loss]
      return navigation_diagnosis if @metrics[:suspicious_navigation]
      return extraction_diagnosis if extraction_failure?

      healthy_diagnosis
    end

    private

    def normalize_hash(value)
      hash_value = value.respond_to?(:to_h) ? value.to_h : {}
      hash_value.is_a?(Hash) ? hash_value.with_indifferent_access : {}.with_indifferent_access
    end

    def wringer_failure?
      return true if @wringer[:unreachable] || @wringer[:received_404] || @wringer[:system_error]
      return true if @wringer_signals[:network_status] == "failed"
      return true if wringer_error_type.present?

      false
    end

    def extraction_failure?
      extraction_attempted? && @metrics[:extraction_empty]
    end

    def error_diagnosis
      if wringer_specific_message(wringer_error_type).present?
        return wringer_diagnosis
      end

      {
        status: :error,
        category: :error,
        message: "Pipeline reported an execution error.",
        suggested_action: :investigate,
        source: "dsl",
        error_type: nil,
        step: @metrics[:failure_step],
        pipeline_category: "unknown",
        details: {
          failure_step: @metrics[:failure_step]
        }
      }
    end

    def wringer_diagnosis
      if wringer_specific_message(wringer_error_type).present?
        return {
          status: :error,
          category: :wringer_failure,
          message: wringer_specific_message(wringer_error_type),
          suggested_action: :retry,
          source: "wringer",
          error_type: wringer_error_type,
          step: @metrics[:failure_step],
          pipeline_category: "fetch",
          details: { wringer: @wringer }
        }
      end

      if @wringer_signals[:network_status] == "failed"
        message =
          if @wringer_hints.include?("timeout")
            "Network timeout occurred during fetch."
          elsif @wringer_hints.include?("empty_body")
            "Fetched page returned empty content."
          else
            "Network request failed before extraction."
          end

        return {
          status: :error,
          category: :wringer_failure,
          message: message,
          suggested_action: :retry,
          source: "wringer",
          error_type: wringer_error_type,
          step: @metrics[:failure_step],
          pipeline_category: "fetch",
          details: { wringer: @wringer }
        }
      end

      if @wringer[:received_404]
        {
          status: :error,
          category: :wringer_failure,
          message: "Wringer returned 404 for the requested resource.",
          suggested_action: :check_url,
          source: "wringer",
          error_type: wringer_error_type,
          step: @metrics[:failure_step],
          pipeline_category: "fetch",
          details: { wringer: @wringer }
        }
      elsif @wringer[:unreachable]
        {
          status: :error,
          category: :wringer_failure,
          message: "Wringer appears unreachable during pipeline execution.",
          suggested_action: :retry,
          source: "wringer",
          error_type: wringer_error_type,
          step: @metrics[:failure_step],
          pipeline_category: "fetch",
          details: { wringer: @wringer }
        }
      else
        {
          status: :error,
          category: :wringer_failure,
          message: "Wringer reported a system-level failure.",
          suggested_action: :check_wringer,
          source: "wringer",
          error_type: wringer_error_type,
          step: @metrics[:failure_step],
          pipeline_category: "fetch",
          details: { wringer: @wringer }
        }
      end
    end

    def data_loss_diagnosis
      {
        status: :warning,
        category: :data_loss,
        message: "Pipeline output lost data between steps.",
        suggested_action: :investigate,
        source: "dsl",
        error_type: nil,
        step: @metrics[:failure_step],
        pipeline_category: "unknown",
        details: {
          failure_step: @metrics[:failure_step],
          recovered_after_loss: @metrics[:recovered_after_loss]
        }
      }
    end

    def navigation_diagnosis
      {
        status: :warning,
        category: :navigation_failure,
        message: "Navigation succeeded, but extraction after navigation produced no data.",
        suggested_action: :check_url,
        source: "dsl",
        error_type: nil,
        step: @metrics[:failure_step],
        pipeline_category: "navigation",
        details: {
          has_navigation: has_navigation?,
          extraction_attempted: extraction_attempted?
        }
      }
    end

    def extraction_diagnosis
      {
        status: :warning,
        category: :extraction_failure,
        message: extraction_message,
        suggested_action: :check_xpath,
        source: "dsl",
        error_type: nil,
        step: @metrics[:failure_step],
        pipeline_category: "extraction",
        details: {
          extraction_attempted: extraction_attempted?,
          extraction_empty: @metrics[:extraction_empty]
        }
      }
    end

    def healthy_diagnosis
      {
        status: :ok,
        category: :healthy,
        message: "Pipeline metrics look healthy.",
        suggested_action: :none,
        source: "dsl",
        error_type: nil,
        step: @metrics[:failure_step],
        pipeline_category: "unknown",
        details: { failure_step: @metrics[:failure_step] }
      }
    end

    def wringer_error_type
      @wringer[:error_type].to_s.presence
    end

    def wringer_specific_message(error_type)
      case error_type.to_s
      when "WringerFetchError"
        "Failed to fetch page (network or upstream service error). No data could be retrieved."
      when "WringerSkip"
        "Request was skipped by upstream policy."
      when "WringerUnsupportedAction"
        "Upstream service returned an unsupported control action."
      end
    end

    def normalize_steps(steps)
      Array(steps).map do |step|
        source = step.respond_to?(:to_h) ? step.to_h : step
        source.is_a?(Hash) ? source.with_indifferent_access : {}.with_indifferent_access
      end
    end

    def extract_steps
      @steps.select { |step| step_primitive(step) == :extract }
    end

    def navigate_steps
      @steps.select { |step| step_primitive(step) == :navigate }
    end

    def extraction_attempted?
      return @metrics[:extraction_attempted] if @steps.empty?

      extract_steps.any?
    end

    def has_navigation?
      return @metrics[:has_navigation] if @steps.empty?

      navigate_steps.any?
    end

    def step_primitive(step)
      primitive = step[:primitive]
      return primitive.to_sym if primitive.present?

      infer_primitive_from_type(step[:type])
    end

    def infer_primitive_from_type(type)
      value = type.to_s

      return :branch if value.start_with?("if_xpath")
      return :extract if value.include?("xpath")
      return :navigate if value.include?("url")
      return :transform if value.include?("ruby")
      return :transform if value.include?("sparql")

      :unknown
    end

    def extraction_message
      if has_navigation? && extract_steps.any?
        "Extraction failed after navigation; no data was produced."
      else
        "Extraction failed; no data was produced."
      end
    end
  end
end
