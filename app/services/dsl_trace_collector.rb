# app/services/dsl_trace_collector.rb
class DslTraceCollector
  def initialize(max_value_len: 2_000, max_events: 200)
    @max_value_len = max_value_len
    @max_events = max_events
    @events = []
  end

  # Called for each DSL step
  # We store a minimal representation of input/output
  def step(step:, type:, code:, input:, output:, error: nil, ms: nil)
    return if @events.length >= @max_events

    @events << {
      step: step,
      type: type,
      code: truncate(code),
      input: truncate(input),
      output: truncate(output),
      error: error && truncate(error),
      ms: ms
    }
  end

  # Return events for rendering
  def to_h
    { events: @events }
  end

  private

  def truncate(v)
    s = v.is_a?(String) ? v : v.inspect
    s.length > @max_value_len ? "#{s[0, @max_value_len]}…(truncated)" : s
  end
end
