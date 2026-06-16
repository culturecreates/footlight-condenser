# app/services/dsl/tracing/trace_collector.rb
module Dsl
  module Tracing
    class TraceCollector
    attr_reader :events

    def initialize
      @events = []
    end

    def step(
      step:,
      type:,
      code:,
      input:,
      output:,
      input_full: nil,
      output_full: nil,
      probe: nil,
      error: nil,
      wringer: nil,
      url_before: nil,
      url_after: nil,
      duration_ms: nil
    )
      compact_error_message =
        case error
        when Hash
          compact_hash_error(error)
        else
          error.nil? ? nil : error.to_s
        end

      @events << {
        step: step,
        type: type,
        code: code,
        input_preview: input,
        output_preview: output,
        input_full: input_full.nil? ? input : input_full,
        output_full: output_full.nil? ? output : output_full,
        probe: probe.present? ? probe : { skipped: true },
        error_class: error.nil? ? nil : error.class.to_s,
        error_message: compact_error_message,
        wringer: wringer.present? ? wringer : { inherited: true },
        url_before: url_before,
        url_after: url_after,
        duration_ms: duration_ms
      }
    end

    def to_h
      @events
    end

    private

    def compact_hash_error(error)
      payload = error.respond_to?(:to_h) ? error.to_h.with_indifferent_access : {}
      error_type = payload[:error_type].presence || "DslAbort"
      step = payload[:step].presence
      message = payload[:error].to_s.tr("\n", " ").squish
      message = "#{message[0, 180]}..." if message.length > 180

      parts = ["Scrape aborted (#{error_type})"]
      parts << "step=#{step}" if step.present?
      parts << message if message.present?
      parts.join(": ")
    end
    end
  end
end
