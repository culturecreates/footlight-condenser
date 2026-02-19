# app/services/dsl_runner.rb
class DslRunner
  def self.process_algorithm(algorithm:, url:, trace: false, trace_opts: {})
    collector = trace ? DslTraceCollector.new(**trace_opts) : DslNullTracer.new

    ctx = DslContext.new(
      url: url,
      array: [],
      tracer: collector
    )

    result = new(ctx: ctx).run(algorithm)

    if trace
      [result, collector.to_h]
    else
      result
    end
  end

  def initialize(ctx:)
    @ctx = ctx
  end

  def run(algorithm)
    # You can delegate to DslAlgorithmRunner,
    # or place shared logic here if needed.
    DslAlgorithmRunner.new(@ctx).run(algorithm)
  end
end
