# app/services/dsl/dsl_null_tracer.rb
module Dsl
  class DslNullTracer
    def step(**); end
    def to_h = {}
  end
end
