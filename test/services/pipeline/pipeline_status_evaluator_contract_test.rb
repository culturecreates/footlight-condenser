require "test_helper"

class PipelineStatusEvaluatorContractTest < ActiveSupport::TestCase
  def call(trace, result = nil)
    Pipeline::PipelineStatusEvaluator.call(result: result, trace: trace)
  end

  test "trace must be an Array" do
    output = Pipeline::PipelineStatusEvaluator.call(
      result: { data: ["ok"] },
      trace: { service: "wringer", error: { error_type: "system_queue" } }
    )

    assert_equal :failed, output[:status]
    assert_equal "dsl_error", output[:error_type]
    assert_output_contract(output)
  end

  test "result must be a Hash or nil" do
    output = Pipeline::PipelineStatusEvaluator.call(
      result: ["abort_update", { error_type: "system_queue" }],
      trace: []
    )

    assert_equal :failed, output[:status]
    assert_equal "dsl_error", output[:error_type]
    assert_output_contract(output)
  end

  test "wringer extraction only includes wringer service events with error present" do
    output = Pipeline::PipelineStatusEvaluator.call(
      result: { data: ["ok"] },
      trace: [
        { service: "other", error: { error_type: "system_cloudflare", retry: true, cache: false } },
        { service: "wringer" },
        { service: "wringer", error: { error_type: "system_queue", retry: true, cache: false } }
      ]
    )

    assert_equal :partial, output[:status]
    assert_equal "system_queue", output[:error_type]
    assert_equal true, output[:retryable]
    assert_equal false, output[:cacheable]
    assert_output_contract(output)
  end

  test "error_type is normalized to lowercase string" do
    output = Pipeline::PipelineStatusEvaluator.call(
      result: { data: ["ok"] },
      trace: [
        { service: "wringer", error: { error_type: "System_Queue", retry: true, cache: false } }
      ]
    )

    assert_equal :partial, output[:status]
    assert_equal "system_queue", output[:error_type]
    assert_output_contract(output)
  end

  test "abort always overrides wringer aggregation" do
    output = Pipeline::PipelineStatusEvaluator.call(
      result: { abort: true, error: "abort now", error_type: "Blocked_Page" },
      trace: [
        { service: "wringer", error: { error_type: "system_cloudflare", retry: true, cache: false } }
      ]
    )

    assert_equal :failed, output[:status]
    assert_equal "blocked_page", output[:error_type]
    assert_output_contract(output)
  end

  test "abort without error_type returns dsl_error" do
    output = Pipeline::PipelineStatusEvaluator.call(
      result: { abort: true, error: "boom" },
      trace: [
        { service: "wringer", error: { error_type: "redirect_to_listing", retry: false, cache: false } }
      ]
    )

    assert_equal :failed, output[:status]
    assert_equal "dsl_error", output[:error_type]
    assert_output_contract(output)
  end

  test "empty trace with valid result returns ok" do
    output = Pipeline::PipelineStatusEvaluator.call(result: { data: ["ok"] }, trace: [])

    assert_equal :ok, output[:status]
    assert_nil output[:error_type]
    assert_output_contract(output)
  end

  test "empty trace with abort returns failed" do
    output = Pipeline::PipelineStatusEvaluator.call(
      result: { abort: true, error: "stop", error_type: "redirect_to_listing" },
      trace: []
    )

    assert_equal :failed, output[:status]
    assert_equal "redirect_to_listing", output[:error_type]
    assert_output_contract(output)
  end

  test "nil result returns failed" do
    output = Pipeline::PipelineStatusEvaluator.call(result: nil, trace: [])

    assert_equal :failed, output[:status]
    assert_equal "dsl_error", output[:error_type]
    assert_output_contract(output)
  end

  test "output contract includes required keys" do
    output = Pipeline::PipelineStatusEvaluator.call(result: { data: ["ok"] }, trace: [])

    assert_output_contract(output)
  end

  test "order of wringer events does not affect result" do
    trace = [
      { service: "wringer", error: true, error_type: "timeout", retry: true },
      { service: "wringer", error: true, error_type: "network", retry: false }
    ]

    base = call(trace)

    10.times do
      assert_equal base, call(trace.shuffle)
    end

    assert_equal base, call(trace.reverse)
  end

  test "same input always produces identical output" do
    trace = [
      { service: "wringer", error: true, error_type: "timeout", retry: true }
    ]

    r1 = call(trace)
    r2 = call(trace)

    assert_equal r1, r2
  end

  test "tie-breaking is deterministic for equivalent severity events" do
    trace = [
      { service: "wringer", error: true, error_type: "alpha", retry: true, cache: true },
      { service: "wringer", error: true, error_type: "beta", retry: true, cache: true }
    ]

    results = []

    20.times do
      results << call(trace.shuffle)
    end

    results.each do |r|
      assert_equal results.first, r
    end
  end

  test "tie-breaking handles nil and mixed types deterministically" do
    trace = [
      { service: "wringer", error: true, error_type: nil, retry: true },
      { service: "wringer", error: true, error_type: "timeout", retry: true }
    ]

    results = []

    20.times do
      results << call(trace.shuffle)
    end

    results.each do |r|
      assert_equal results.first, r
    end
  end

  test "ignores garbage entries safely" do
    trace = [
      nil,
      "oops",
      123,
      {},
      [],
      { foo: "bar" },
      { service: "wringer", error: true, error_type: "timeout" }
    ]

    result = call(trace)

    assert result.is_a?(Hash)
    assert_includes [:ok, :partial, :failed], result[:status]
  end

  test "handles incomplete wringer events safely" do
    trace = [
      { service: "wringer" },
      { wringer: {} }
    ]

    result = call(trace)

    assert result.is_a?(Hash)
  end

  test "handles string keys the same as symbol keys" do
    trace_symbol = [
      { service: "wringer", error: true, error_type: "timeout" }
    ]

    trace_string = [
      { "service" => "wringer", "error" => true, "error_type" => "timeout" }
    ]

    assert_equal call(trace_symbol), call(trace_string)
  end

  test "handles unexpected error_type values safely" do
    trace = [
      { service: "wringer", error: true, error_type: Object.new }
    ]

    result = call(trace)

    assert result[:error_type].nil? || result[:error_type].is_a?(String)
  end

  # IMPORTANT:
  # nil result represents a failed/invalid pipeline execution.
  # An empty but valid result must be expressed explicitly as a Hash.
  # This test verifies that an empty trace + valid result is considered OK.
  test "empty trace yields ok and cacheable" do
    result = call([], { data: [] })

    assert_equal :ok, result[:status]
    assert_equal true, result[:cacheable]
  end

  test "abort overrides all trace events" do
    trace = [
      { service: "wringer", error: true, error_type: "timeout", retry: true }
    ]

    result = call(trace, { abort: true, error_type: "fatal" })

    assert_equal :failed, result[:status]
    assert_equal false, result[:retryable]
    assert_equal false, result[:cacheable]
    assert_equal :abort, result[:reason]
  end

  test "supports mixed legacy and new wringer formats" do
    trace = [
      { service: "wringer", error: true, error_type: "timeout" },
      { wringer: { error_type: "network", retry: true } }
    ]

    result = call(trace)

    assert result[:status]
  end

  private

  def assert_output_contract(output)
    required = %i[status error_type retryable cacheable reason]
    assert_equal required.sort, output.keys.sort
  end
end
