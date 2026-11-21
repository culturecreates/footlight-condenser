require "test_helper"

class Distillator::FetchShadowComparatorTest < ActiveSupport::TestCase
  class CapturingLogger
    attr_reader :infos, :warnings

    def initialize
      @infos = []
      @warnings = []
    end

    def info(payload)
      @infos << payload
    end

    def warn(payload)
      @warnings << payload
    end
  end

  test "logs structured mismatch without full body" do
    logger = CapturingLogger.new
    legacy = fetch_response(body: "<html>legacy</html>", final_url: "https://example.com/legacy")
    internal = fetch_response(body: "<html>internal</html>", final_url: "https://example.com/internal")

    mismatches = Distillator::FetchShadowComparator.compare(
      url: "https://example.com/events",
      legacy: legacy,
      internal: internal,
      logger: logger
    )

    assert_equal false, logger.infos.first[:matched]
    assert_includes mismatches.map { |item| item[:field] }, :body_hash
    assert_includes mismatches.map { |item| item[:field] }, :final_url
    refute_includes logger.infos.first.inspect, "<html>legacy</html>"
    refute_includes logger.infos.first.inspect, "<html>internal</html>"
  end

  test "returns empty mismatches for equivalent comparison fields" do
    logger = CapturingLogger.new
    response = fetch_response

    mismatches = Distillator::FetchShadowComparator.compare(
      url: "https://example.com/events",
      legacy: response,
      internal: response,
      logger: logger
    )

    assert_equal [], mismatches
    assert_equal true, logger.infos.first[:matched]
  end

  test "never raises comparator errors to caller" do
    logger = CapturingLogger.new
    broken = Object.new
    broken.define_singleton_method(:[]) { |_key| raise "boom" }

    assert_nil Distillator::FetchShadowComparator.compare(
      url: "https://example.com/events",
      legacy: broken,
      internal: fetch_response,
      logger: logger
    )
    assert_equal "distillator.fetch_shadow.compare_error", logger.warnings.first[:event]
  end

  private

  def fetch_response(body: "<html>ok</html>", final_url: "https://example.com/final")
    {
      status: :ok,
      body: body,
      headers: { content_type: "text/html" },
      final_url: final_url,
      redirect_chain: ["https://example.com/start", final_url],
      wringer: {
        error_type: nil,
        received_404: false,
        system_error: false,
        unreachable: false
      }
    }
  end
end
