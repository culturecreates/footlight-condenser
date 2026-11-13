# app/services/dsl/tracing/null_tracer.rb
module Dsl
  module Tracing
    class NullTracer
    def step(**); end
    def to_h = []
    end
  end
end
