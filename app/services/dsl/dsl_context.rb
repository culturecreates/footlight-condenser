# app/services/dsl/dsl_context.rb
module Dsl
  class DslContext
    attr_reader :url, :array, :tracer

    def initialize(url:, array:, tracer:)
      @url     = url
      @array   = array
      @tracer  = tracer
    end
  end
end