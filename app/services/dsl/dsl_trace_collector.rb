# app/services/dsl/dsl_trace_collector.rb
module Dsl
  class DslTraceCollector
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
        error_message: error.nil? ? nil : error.to_s,
        wringer: wringer.present? ? wringer : { inherited: true },
        url_before: url_before,
        url_after: url_after,
        duration_ms: duration_ms
      }
    end

    def to_h
      @events
    end
  end
end
