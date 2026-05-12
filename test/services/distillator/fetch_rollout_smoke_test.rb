require "test_helper"

class Distillator::FetchRolloutSmokeTest < ActiveSupport::TestCase
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

  setup do
    @old_fetch_mode = ENV["DISTILLATOR_FETCH_MODE"]
    @old_replay_fetch = ENV["REPLAY_FETCH"]
    ENV["REPLAY_FETCH"] = nil
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_fetch_mode
    ENV["REPLAY_FETCH"] = @old_replay_fetch
  end

  test "shadow mode returns legacy result and emits comparison log without live network" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new
    legacy_result = fetch_result(body: "<html>legacy</html>")
    internal_result = fetch_result(body: "<html>internal</html>")

    Distillator::FetchService.expects(:legacy_fetch).returns(legacy_result)
    Distillator::FetchService.expects(:guarded_internal_fetch).returns(internal_result)

    result = Distillator::FetchService.fetch(
      url: "https://example.com/events",
      mode: :shadow,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call },
      logger: logger
    )

    assert_equal "<html>legacy</html>", result[:body]
    assert_equal(
      [:body, :duration_ms, :final_url, :headers, :redirect_chain, :status, :wringer],
      result.keys.sort
    )
    events = logger.infos.map { |entry| entry[:event] }
    assert_includes events, "distillator.fetch.eligibility"
    assert_includes events, "distillator.fetch_shadow.compare"
    assert_includes events, "fetch.shadow_compare"

    eligibility_index = events.index("distillator.fetch.eligibility")
    compare_index = events.index("distillator.fetch_shadow.compare")
    assert_operator eligibility_index, :<, compare_index

    compare_payload = logger.infos.find { |entry| entry[:event] == "distillator.fetch_shadow.compare" }
    assert_equal false, compare_payload[:matched]
    assert_includes compare_payload[:mismatches].map { |item| item[:field] }, :body_hash

    outcome_payload = logger.infos.find { |entry| entry[:event] == "fetch.shadow_compare" }
    assert_equal "explicit", outcome_payload[:mode_source]
  end

  test "guard-blocked shadow request skips compare and returns abort" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    logger = CapturingLogger.new

    Distillator::FetchService.expects(:legacy_fetch).never
    Distillator::FetchService.expects(:internal_fetch).never
    Distillator::FetchShadowComparator.expects(:compare).never

    result = Distillator::FetchService.fetch(
      url: "http://127.0.0.1/events",
      mode: :shadow,
      use_wringer: ->(*_) { "wringer://resolved" },
      safe_wringer_call: ->(&blk) { blk.call },
      logger: logger
    )

    assert_equal :abort, result[:status]
    assert_equal "distillator.fetch_mode.internal_ineligible", logger.infos.first[:event]
    assert_equal :blocked_url, logger.infos.first[:reason]
    assert_equal "distillator.fetch_shadow.skipped", logger.infos.second[:event]
    assert_equal :blocked_url, logger.infos.second[:reason]
  end

  private

  def fetch_result(body:)
    {
      status: :ok,
      body: body,
      headers: { content_type: "text/html" },
      final_url: "https://example.com/events",
      redirect_chain: ["https://example.com/events"],
      wringer: {
        signals: {},
        hints: [],
        error_type: nil,
        received_404: false,
        system_error: false,
        unreachable: false
      }
    }
  end
end
