module Dsl
  class PipelineDiagnosis
    def initialize(metrics:, wringer: {})
      @metrics = normalize_hash(metrics)
      @wringer = normalize_hash(wringer)
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
      @wringer[:unreachable] || @wringer[:received_404] || @wringer[:system_error]
    end

    def extraction_failure?
      @metrics[:extraction_attempted] && @metrics[:extraction_empty]
    end

    def error_diagnosis
      {
        status: :error,
        category: :error,
        message: "Pipeline reported an execution error.",
        suggested_action: :investigate,
        details: {
          failure_step: @metrics[:failure_step]
        }
      }
    end

    def wringer_diagnosis
      if @wringer[:received_404]
        {
          status: :error,
          category: :wringer_failure,
          message: "Wringer returned 404 for the requested resource.",
          suggested_action: :check_url,
          details: { wringer: @wringer }
        }
      elsif @wringer[:unreachable]
        {
          status: :error,
          category: :wringer_failure,
          message: "Wringer appears unreachable during pipeline execution.",
          suggested_action: :retry,
          details: { wringer: @wringer }
        }
      else
        {
          status: :error,
          category: :wringer_failure,
          message: "Wringer reported a system-level failure.",
          suggested_action: :check_wringer,
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
        message: "Navigation likely contributed to extraction issues; post-navigation extraction appears empty.",
        suggested_action: :check_url,
        details: {
          has_navigation: @metrics[:has_navigation],
          extraction_attempted: @metrics[:extraction_attempted]
        }
      }
    end

    def extraction_diagnosis
      {
        status: :warning,
        category: :extraction_failure,
        message: "Extraction was attempted but returned no usable data.",
        suggested_action: :check_xpath,
        details: {
          extraction_attempted: @metrics[:extraction_attempted],
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
        details: { failure_step: @metrics[:failure_step] }
      }
    end
  end
end
