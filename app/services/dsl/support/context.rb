# app/services/dsl/support/context.rb
module Dsl
  module Support
    class Context
    attr_reader :url, :array, :tracer

    def initialize(url:, array:, tracer:)
      @url     = url
      @array   = array
      @tracer  = tracer
    end
    end
  end
end
