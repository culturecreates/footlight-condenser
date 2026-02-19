# app/services/dsl_runner.rb
def process_algorithm(algorithm:, url:, trace: false, trace_opts: {})
  collector = trace ? DslTraceCollector.new(**trace_opts) : DslNullTracer.new

  ctx = DslContext.new(
    url: url,
    array: [],
    tracer: collector
  )

  result = DslRunner.new(ctx: ctx).run(algorithm)

  if trace
    [result, collector.to_h]   # or collector.events
  else
    result
  end
end
