# app/services/dsl/dsl_runner.rb
module Dsl
  class DslRunner
    def self.process_algorithm(algorithm:, url:, trace: false, trace_opts: {})
        
      # 🎯 Decide tracer type:
      collector = trace ? Dsl::DslTraceCollector.new(**trace_opts) : Dsl::DslNullTracer.new

      # 📌 Build base context
      ctx = Dsl::DslContext.new(
        url: url,
        array: [],
        tracer: collector
      )

      # 🛠 Run the internal runner
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
      # Delegate to your existing core runner
      Dsl::DslAlgorithmRunner.new(@ctx).run(algorithm)
    end
  end
end