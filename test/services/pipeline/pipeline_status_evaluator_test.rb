require "test_helper"

class PipelineStatusEvaluatorTest < ActiveSupport::TestCase
  test "multiple wringer events partial plus failed resolves to failed" do
    result = { data: ["ok"] }
    trace = [
      { wringer: { error_type: "system_queue", retry: true, cache: true } },
      { wringer: { error_type: "redirect_to_listing", retry: false, cache: false } }
    ]

    output = Pipeline::PipelineStatusEvaluator.call(result: result, trace: trace)

    assert_equal :failed, output[:status]
    assert_equal "redirect_to_listing", output[:error_type]
    assert_equal true, output[:retryable]
    assert_equal false, output[:cacheable]
    assert_equal :invalid_event_page, output[:reason]
  end

  test "multiple wringer events aggregate retryable with any true" do
    result = { data: ["ok"] }
    trace = [
      { wringer: { error_type: "system_cloudflare", retry: false, cache: true } },
      { wringer: { error_type: "system_queue", retry: true, cache: true } }
    ]

    output = Pipeline::PipelineStatusEvaluator.call(result: result, trace: trace)

    assert_equal :partial, output[:status]
    assert_equal true, output[:retryable]
  end

  test "multiple wringer events aggregate cacheable with all true" do
    result = { data: ["ok"] }
    trace = [
      { wringer: { error_type: "system_cloudflare", retry: true, cache: true } },
      { wringer: { error_type: "system_queue", retry: true, cache: false } }
    ]

    output = Pipeline::PipelineStatusEvaluator.call(result: result, trace: trace)

    assert_equal :partial, output[:status]
    assert_equal false, output[:cacheable]
  end

  test "fatal error overrides partial status" do
    result = { data: ["ok"] }
    trace = [
      { wringer: { error_type: "system_cloudflare", retry: true, cache: true } },
      { wringer: { error_type: "blocked_page", retry: false, cache: false } }
    ]

    output = Pipeline::PipelineStatusEvaluator.call(result: result, trace: trace)

    assert_equal :failed, output[:status]
    assert_equal "blocked_page", output[:error_type]
  end

  test "empty trace with valid result returns ok" do
    output = Pipeline::PipelineStatusEvaluator.call(result: { data: ["ok"] }, trace: [])

    assert_equal :ok, output[:status]
    assert_nil output[:error_type]
    assert_equal false, output[:retryable]
    assert_equal true, output[:cacheable]
    assert_nil output[:reason]
  end

  test "nil result returns failed dsl_error" do
    output = Pipeline::PipelineStatusEvaluator.call(result: nil, trace: [])

    assert_equal :failed, output[:status]
    assert_equal "dsl_error", output[:error_type]
    assert_equal false, output[:retryable]
    assert_equal false, output[:cacheable]
  end

  test "abort without error_type returns failed dsl_error" do
    result = { abort: true, error: "boom" }

    output = Pipeline::PipelineStatusEvaluator.call(result: result, trace: [])

    assert_equal :failed, output[:status]
    assert_equal "dsl_error", output[:error_type]
    assert_equal false, output[:retryable]
    assert_equal false, output[:cacheable]
  end

  test "last error wins when severity is equal" do
    result = { data: ["ok"] }
    trace = [
      { wringer: { error_type: "system_cloudflare", retry: false, cache: true } },
      { wringer: { error_type: "system_queue", retry: false, cache: true } }
    ]

    output = Pipeline::PipelineStatusEvaluator.call(result: result, trace: trace)

    assert_equal :partial, output[:status]
    assert_equal "system_queue", output[:error_type]
  end
end
