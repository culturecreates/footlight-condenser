module Pipeline
  class PipelineStatusEvaluator
    # IMPORTANT:
    # - Evaluator is pure and deterministic
    # - Does NOT rely on trace ordering
    # - Does NOT raise on invalid input (fault-tolerant)
    # - Wringer rules are NOT reimplemented here
    STATUS_PRIORITY = {
      ok: 1,
      partial: 2,
      failed: 3
    }.freeze

    FATAL_ERROR_TYPES = %w[
      redirect_to_listing
      invalid_event_page
      blocked_page
    ].freeze

    def self.call(result:, trace:)
      new(result: result, trace: trace).call
    end

    def initialize(result:, trace:)
      @result = result
      @trace = trace
    end

    def call
      invalid_input = invalid_input?
      trace = @trace.is_a?(Array) ? @trace.compact : []
      result = @result.is_a?(Hash) || @result.nil? ? @result : nil

      return failure_response("dsl_error") if invalid_input
      return failure_response("dsl_error") if result.nil?
      return abort_response(result) if abort?(result)

      events = extract_wringer_events(trace).map { |event| normalize_event(event) }.compact
      return aggregated_ok(events) if events.empty?

      event = aggregate_event(events)
      error_type = event[:error_type]

      {
        status: status_for_event(event),
        error_type: error_type,
        retryable: aggregate_retryable(events),
        cacheable: aggregate_cacheable(events),
        reason: reason_for(error_type)
      }
    end

    private

    def invalid_input?
      trace_invalid = !@trace.is_a?(Array)
      result_invalid = !@result.is_a?(Hash) && !@result.nil?
      trace_invalid || result_invalid
    end

    def extract_wringer_events(trace)
      trace.select { |event| wringer_event?(event) }
    end

    def wringer_event?(event)
      return false unless event.is_a?(Hash)
      return true if value_for(event, :service) == "wringer" && value_for(event, :error).present?
      return true if value_for(event, :wringer).is_a?(Hash)

      false
    end

    def normalize_event(event)
      if value_for(event, :service) == "wringer"
        normalize_new_wringer_event(event)
      elsif value_for(event, :wringer).is_a?(Hash)
        normalize_legacy_wringer_event(value_for(event, :wringer))
      end
    end

    def normalize_new_wringer_event(event)
      payload = value_for(event, :error)
      payload = event unless payload.is_a?(Hash)

      {
        error_type: normalize_error(value_for(payload, :error_type)),
        retryable: !!value_for(payload, :retry),
        cacheable: !!value_for(payload, :cache)
      }
    end

    def normalize_legacy_wringer_event(payload)
      {
        error_type: normalize_error(value_for(payload, :error_type)),
        retryable: !!value_for(payload, :retry),
        cacheable: !!value_for(payload, :cache)
      }
    end

    def normalize_error(error_type)
      return nil if error_type.nil?

      normalized = error_type.to_s.underscore.downcase
      normalized.empty? ? nil : normalized
    end

    def abort?(result)
      return false unless result.is_a?(Hash)

      value_for(result, :abort) == true || !value_for(result, :error).nil?
    end

    def extract_abort_error(result)
      normalize_error(value_for(result, :error_type)) || "dsl_error"
    end

    def status_for_event(event)
      fatal_error?(event) ? :failed : :partial
    end

    def fatal_error?(event)
      FATAL_ERROR_TYPES.include?(event[:error_type].to_s)
    end

    def aggregate_event(events)
      events.max_by do |event|
        [STATUS_PRIORITY.fetch(status_for_event(event), 0), event[:error_type].to_s]
      end
    end

    def value_for(hash, key)
      return hash[key] if hash.key?(key)
      return hash[key.to_s] if hash.key?(key.to_s)

      nil
    end

    def reason_for(error_type)
      return :invalid_event_page if error_type == "redirect_to_listing"
      return :invalid_event_page if error_type == "invalid_event_page"
      return :blocked_page if error_type == "blocked_page"

      nil
    end

    def aggregate_retryable(events)
      events.any? { |event| event[:retryable] }
    end

    def aggregate_cacheable(events)
      events.empty? || events.all? { |event| event[:cacheable] }
    end

    def aggregated_ok(_events)
      {
        status: :ok,
        error_type: nil,
        retryable: false,
        cacheable: true,
        reason: nil
      }
    end

    def abort_response(result)
      {
        status: :failed,
        error_type: extract_abort_error(result),
        retryable: false,
        cacheable: false,
        reason: :abort
      }
    end

    def failure_response(error_type)
      {
        status: :failed,
        error_type: error_type,
        retryable: false,
        cacheable: false,
        reason: reason_for(error_type)
      }
    end
  end
end
