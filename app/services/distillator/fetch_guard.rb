module Distillator
  class FetchGuard
    Result = Struct.new(:allowed, :error, :reason, :normalized_url, keyword_init: true) do
      def allowed?
        allowed
      end
    end

    def self.check_url(url, resolver: Resolv)
      new(resolver: resolver).check_url(url)
    end

    def self.check_response(response, resolver: Resolv)
      new(resolver: resolver).check_response(response)
    end

    def initialize(resolver: Resolv)
      @policy = Distillator::UrlSafetyPolicy.new(resolver: resolver)
    end

    def check_url(url)
      from_decision(policy.check_url(url))
    end

    def check_response(response)
      from_decision(policy.check_response(response))
    end

    private

    attr_reader :policy

    def from_decision(decision)
      Result.new(
        allowed: decision.allowed?,
        error: decision.message,
        reason: decision.reason,
        normalized_url: decision.normalized_url
      )
    end
  end
end
