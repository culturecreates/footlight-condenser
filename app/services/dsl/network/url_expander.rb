# app/services/dsl/network/url_expander.rb
module Dsl
  module Network
    class UrlExpander
      def self.call(url, context: nil, agent: nil)
        resolved_agent = agent || context&.instance_variable_get(:@agent)
        new(url, resolved_agent).call
      end

      def initialize(url, agent)
        @url   = url
        @agent = agent
      end

      def call
        response = @agent.get(@url)
        response.uri.to_s
      rescue StandardError
        @url
      end
    end
  end
end
