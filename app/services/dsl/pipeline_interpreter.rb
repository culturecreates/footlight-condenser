module Dsl
  class PipelineInterpreter
    def initialize(steps)
      @steps = Array(steps).map do |step|
        source = step.respond_to?(:to_h) ? step.to_h : step
        source.is_a?(Hash) ? source.with_indifferent_access : {}
      end
    end

    def metrics
      metric_values = {
        # Truth signals: these report what was observed in the pipeline.
        error_present: error_present?,
        data_loss: data_loss?,
        extraction_empty: extraction_empty?,
        extraction_attempted: extraction_attempted?,
        # Pre-diagnosis fetch-layer suspicion signal (Wringer wiring comes later).
        suspicious_navigation: suspicious_navigation?,
        # Best-effort location metadata; may be nil when no step number is available.
        failure_step: failure_step,
        recovered_after_loss: recovered_after_loss?,
        steps_count: @steps.size,
        final_empty: final_empty?,
        has_navigation: has_navigation?
      }

      enforce_consistency(metric_values)
    end

    private

    def outputs
      Array(@steps).map do |step|
        step.is_a?(Hash) ? step[:output] : nil
      end
    end

    def error_present?
      first_error_step.present?
    end

    def data_loss?
      transition_loss_kinds.any?
    end

    def extraction_empty?
      return false unless extraction_attempted?

      final_empty?
    end

    def extraction_attempted?
      @steps.any? { |step| step_primitive(step) == :extract }
    end

    def suspicious_navigation?
      return false unless has_navigation?

      navigation_index = @steps.find_index { |step| step_primitive(step) == :navigate }
      return false if navigation_index.nil?

      post_navigation_steps = @steps[(navigation_index + 1)..] || []
      extraction_steps = post_navigation_steps.take_while do |step|
        step_primitive(step) == :extract
      end

      return false if extraction_steps.empty?

      extraction_steps.all? { |step| blank?(step[:output]) }
    end

    def failure_step
      first_error = first_error_step
      return extract_step_number(first_error) if first_error

      return nil unless extraction_attempted?
      return nil unless final_empty?

      extract_step_number(@steps.last)
    end

    def recovered_after_loss?
      lost = false
      outputs.each_cons(2).any? do |prev, curr|
        lost ||= transition_loss_kind(prev, curr).present?
        lost && transition_recovered?(prev, curr)
      end
    end

    def final_empty?
      blank?(outputs.last)
    end

    def has_navigation?
      @steps.any? { |step| step_primitive(step) == :navigate }
    end

    def step_type(step)
      step.is_a?(Hash) ? step[:type].to_s : ""
    end

    def step_primitive(step)
      return :unknown unless step.is_a?(Hash)

      (step[:primitive]&.to_sym) || infer_primitive_from_type(step[:type])
    end

    def infer_primitive_from_type(type)
      t = type.to_s

      return :branch if t.start_with?("if_xpath")
      return :extract if t.include?("xpath")
      return :navigate if t.include?("url")
      return :transform if t.include?("ruby")
      return :transform if t.include?("sparql")

      :unknown
    end

    def blank?(value)
      normalized = normalize_output(value)
      normalized.nil? || (normalized.respond_to?(:empty?) && normalized.empty?)
    end

    def extract_step_number(step)
      return nil unless step.is_a?(Hash)

      step[:step].presence
    end

    def first_error_step
      @steps.find { |s| s[:error].present? }
    end

    def first_loss_step
      @steps.each_cons(2) do |prev, curr|
        prev_output = prev.is_a?(Hash) ? prev[:output] : nil
        curr_output = curr.is_a?(Hash) ? curr[:output] : nil
        return curr if transition_loss_kind(prev_output, curr_output).present?
      end

      nil
    end

    def transition_loss_kind(previous, current)
      previous_normalized = normalize_output(previous)
      current_normalized = normalize_output(current)

      return :full_loss if present_normalized?(previous_normalized) && blank_normalized?(current_normalized)
      return :partial_loss if previous_normalized.is_a?(Array) &&
                              current_normalized.is_a?(Array) &&
                              current_normalized.size < previous_normalized.size

      nil
    end

    def transition_loss_kinds
      outputs.each_cons(2).map do |prev, curr|
        transition_loss_kind(prev, curr)
      end.compact
    end

    def transition_recovered?(previous, current)
      previous_normalized = normalize_output(previous)
      current_normalized = normalize_output(current)

      return false if blank_normalized?(current_normalized)
      return true if blank_normalized?(previous_normalized) && present_normalized?(current_normalized)

      previous_normalized.is_a?(Array) &&
        current_normalized.is_a?(Array) &&
        current_normalized.size > previous_normalized.size
    end

    def normalize_output(value)
      return nil if value.nil?
      return nil if value.is_a?(String) && value.strip.empty?
      return value.compact if value.is_a?(Array)

      value
    end

    def blank_normalized?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def present_normalized?(value)
      !blank_normalized?(value)
    end

    def extraction_xpath_steps
      @steps.select { |step| step[:type].to_s.include?("xpath") }
    end

    def enforce_consistency(metric_values)
      # Keep truth signals untouched; failure_step is best-effort location metadata.
      metric_values
    end
  end
end
