require "test_helper"

class Distillator::FetchGuardTest < ActiveSupport::TestCase
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

  class MappingResolver
    def initialize(mapping)
      @mapping = mapping
    end

    def getaddresses(host)
      @mapping.fetch(host, [])
    end
  end

  test "allows https public hostname" do
    result = Distillator::FetchGuard.check_url(
      "https://example.org/events",
      resolver: StaticResolver.new(["93.184.216.34"])
    )

    assert result.allowed?
    assert_equal "https://example.org/events", result.normalized_url
  end

  test "allows http public hostname like wringer safe_url" do
    result = Distillator::FetchGuard.check_url(
      "http://example.org/events",
      resolver: StaticResolver.new(["93.184.216.34"])
    )

    assert result.allowed?
    assert_equal "http://example.org/events", result.normalized_url
  end

  test "blocks localhost" do
    result = Distillator::FetchGuard.check_url(
      "http://localhost/events",
      resolver: StaticResolver.new([])
    )

    refute result.allowed?
    assert_includes result.error, "localhost"
    assert_equal :blocked_localhost, result.reason
  end

  test "blocks 127.0.0.1:3009 like legacy safe_url" do
    result = refute_allowed("http://127.0.0.1:3009")

    assert_includes result.error, "127.0.0.1"
  end

  test "blocks localhost hostname exactly" do
    result = Distillator::FetchGuard.check_url(
      "http://localhost",
      resolver: StaticResolver.new([])
    )

    refute result.allowed?
    assert_includes result.error, "localhost"
  end

  test "blocks 10.0.0.1 like legacy safe_url" do
    result = refute_allowed("http://10.0.0.1")

    assert_includes result.error, "10.0.0.1"
  end

  test "blocks 169.254.169.254 like legacy safe_url" do
    result = refute_allowed("http://169.254.169.254")

    assert_includes result.error, "169.254.169.254"
  end

  test "blocks file scheme like legacy safe_url" do
    result = Distillator::FetchGuard.check_url(
      "file:///etc/passwd",
      resolver: StaticResolver.new([])
    )

    refute result.allowed?
    assert_includes result.error, "scheme"
    assert_equal :blocked_scheme, result.reason
  end

  test "allows http example.org like legacy safe_url" do
    result = Distillator::FetchGuard.check_url(
      "http://example.org",
      resolver: StaticResolver.new(["93.184.216.34"])
    )

    assert result.allowed?
  end

  test "blocks 192.168.0.0/16" do
    result = refute_allowed("http://192.168.1.5/events")

    assert_includes result.error, "192.168.1.5"
  end

  test "blocks every 172.16.0.0/12 legacy private range boundary" do
    %w[172.16.0.1 172.20.10.5 172.31.255.254].each do |ip|
      result = refute_allowed("http://#{ip}/events")

      assert_includes result.error, ip
    end
  end

  test "blocks ipv6 loopback ::1" do
    result = refute_allowed("http://[::1]/events")

    assert_includes result.error, "::1"
  end

  test "blocks ipv6 unique local fc00::/7" do
    %w[fc00::1 fd12:3456:789a::1].each do |ip|
      result = refute_allowed("http://[#{ip}]/events")

      assert_includes result.error, ip
    end
  end

  test "blocks ipv6 link local fe80::/10" do
    %w[fe80::1 febf::abcd].each do |ip|
      result = refute_allowed("http://[#{ip}]/events")

      assert_includes result.error, ip
    end
  end

  test "blocks DNS resolution to private IP deterministically" do
    result = Distillator::FetchGuard.check_url(
      "https://private.example/events",
      resolver: StaticResolver.new(["10.1.2.3"])
    )

    refute result.allowed?
    assert_includes result.error, "10.1.2.3"
    assert_includes result.error, "private.example"
    assert_equal :blocked_private_ip, result.reason
  end

  test "blocks DNS ambiguity when resolver returns no addresses" do
    result = Distillator::FetchGuard.check_url(
      "https://missing.example/events",
      resolver: StaticResolver.new([])
    )

    refute result.allowed?
    assert_equal :dns_resolution_failed, result.reason
    assert_includes result.error, "no DNS resolution result"
  end

  test "blocks DNS resolver exceptions instead of allowing through" do
    result = Distillator::FetchGuard.check_url(
      "https://timeout.example/events",
      resolver: RaisingResolver.new(Timeout::Error.new("execution expired"))
    )

    refute result.allowed?
    assert_equal :dns_resolution_error, result.reason
    assert_includes result.error, "Timeout::Error"
  end

  test "allows DNS hostname when stubbed resolver returns public IP" do
    result = Distillator::FetchGuard.check_url(
      "https://public.example/events",
      resolver: StaticResolver.new(["93.184.216.34"])
    )

    assert result.allowed?
  end

  test "blocks redirect_chain containing private IP" do
    result = Distillator::FetchGuard.check_response(
      {
        final_url: "https://example.org/final",
        redirect_chain: ["https://example.org/start", "http://192.168.1.2/redirect"]
      },
      resolver: StaticResolver.new(["93.184.216.34"])
    )

    refute result.allowed?
    assert_includes result.error, "192.168.1.2"
    assert_equal :blocked_private_ip, result.reason
  end

  test "blocks unsafe final url even when redirect chain itself looks public" do
    resolver = MappingResolver.new("example.org" => ["93.184.216.34"])
    result = Distillator::FetchGuard.check_response(
      {
        final_url: "http://169.254.169.254/latest/meta-data",
        redirect_chain: ["https://example.org/start", "https://example.org/final"]
      },
      resolver: resolver
    )

    refute result.allowed?
    assert_equal :blocked_private_ip, result.reason
    assert_includes result.error, "169.254.169.254"
  end

  test "blocked result includes caller-usable error details" do
    result = Distillator::FetchGuard.check_url(
      "http://localhost/events",
      resolver: StaticResolver.new([])
    )

    refute result.allowed?
    assert_kind_of String, result.error
    assert_includes result.error, "Blocked"
    assert_equal :blocked_localhost, result.reason
    assert_nil result.normalized_url
  end

  test "blocks unresolved host instead of treating it as public unknown" do
    result = Distillator::FetchGuard.check_url(
      "https://missing.example/events",
      resolver: stub(getaddresses: [])
    )

    refute result.allowed?
    assert_equal :dns_resolution_failed, result.reason
  end

  private

  def refute_allowed(url)
    result = Distillator::FetchGuard.check_url(url, resolver: StaticResolver.new([]))

    refute result.allowed?, "#{url} should be blocked"
    assert_includes result.error, "Blocked"
    result
  end
end
