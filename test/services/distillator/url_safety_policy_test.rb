require "test_helper"

class Distillator::UrlSafetyPolicyTest < ActiveSupport::TestCase
  class StaticResolver
    def initialize(addresses)
      @addresses = addresses
    end

    def getaddresses(_host)
      @addresses
    end
  end

  class RaisingResolver
    def initialize(error)
      @error = error
    end

    def getaddresses(_host)
      raise @error
    end
  end

  test "blocks blank dns resolution result" do
    decision = Distillator::UrlSafetyPolicy.check_url(
      "https://missing.example/events",
      resolver: StaticResolver.new([])
    )

    refute decision.allowed?
    assert_equal :dns_resolution_failed, decision.reason
    assert_includes decision.message, "no DNS resolution result"
  end

  test "blocks dns resolver exceptions" do
    decision = Distillator::UrlSafetyPolicy.check_url(
      "https://timeout.example/events",
      resolver: RaisingResolver.new(Timeout::Error.new("execution expired"))
    )

    refute decision.allowed?
    assert_equal :dns_resolution_error, decision.reason
    assert_includes decision.message, "Timeout::Error"
  end

  test "allows public http and https urls when dns resolves publicly" do
    http_decision = Distillator::UrlSafetyPolicy.check_url(
      "http://example.org/events",
      resolver: StaticResolver.new(["93.184.216.34"])
    )
    https_decision = Distillator::UrlSafetyPolicy.check_url(
      "https://example.org/events",
      resolver: StaticResolver.new(["93.184.216.34"])
    )

    assert http_decision.allowed?
    assert https_decision.allowed?
  end

  test "blocks final url that resolves to private ip after redirect handling" do
    decision = Distillator::UrlSafetyPolicy.check_response(
      {
        final_url: "https://private.example/final",
        redirect_chain: ["https://example.org/start"]
      },
      resolver: StaticResolver.new(["10.0.0.1"])
    )

    refute decision.allowed?
    assert_equal :blocked_private_ip, decision.reason
    assert_includes decision.message, "10.0.0.1"
  end
end
