# app/services/dsl_trace_collector.rb
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
    error: nil,
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
      error_class: error.nil? ? nil : error.class.to_s,
      error_message: error.nil? ? nil : error.to_s,
      url_before: url_before,
      url_after: url_after,
      duration_ms: duration_ms
    }
  end

  def to_h
    @events
  end
end