require "test_helper"

class Dsl::TraceFormatterTest < ActiveSupport::TestCase
  test "for_ui truncates long strings" do
    formatted = Dsl::TraceFormatter.for_ui([
      {
        step: 1,
        type: "ruby",
        code: "x" * 400,
        input_preview: ["in"],
        output_preview: ["out"]
      }
    ])

    assert_equal 1, formatted.length
    assert_equal 203, formatted.first[:code].length
    assert_equal("...", formatted.first[:code][-3, 3])
  end

  test "format_value summarizes arrays with size and sample" do
    value = (1..10).to_a

    formatted = Dsl::TraceFormatter.format_value(value)

    assert_match(/\A\[Array size=10, sample=/, formatted)
    assert_includes formatted, "1"
    assert_includes formatted, "5"
    refute_includes formatted, "6"
  end

  test "format_value converts exceptions to message" do
    formatted = Dsl::TraceFormatter.format_value(StandardError.new("boom"))

    assert_equal "boom", formatted
  end

  test "format_value preserves nil" do
    assert_nil Dsl::TraceFormatter.format_value(nil)
  end

  test "for_ui handles mixed hash and to_h structures" do
    step_like = Struct.new(:payload) do
      def to_h
        payload
      end
    end

    input = [
      {
        step: 1,
        type: "xpath",
        code: "//a",
        input_preview: ["one"],
        output_preview: ["two"],
        error_class: nil,
        error_message: nil,
        url_before: "https://example.com/1",
        url_after: "https://example.com/1",
        duration_ms: 1.1
      },
      step_like.new(
        {
          step: 2,
          type: "ruby",
          code: "$array.map(&:upcase)",
          input_preview: ["a"],
          output_preview: ["A"],
          error_class: "RuntimeError",
          error_message: "failed",
          url_before: "https://example.com/2",
          url_after: "https://example.com/2",
          duration_ms: 2.2
        }
      )
    ]

    formatted = Dsl::TraceFormatter.for_ui(input)

    assert_equal 2, formatted.length
    assert_equal "xpath", formatted.first[:type]
    assert_match(/\A\[Array size=1, sample=\[\"one\"\]\]\z/, formatted.first[:input])
    assert_equal "RuntimeError: failed", formatted.second[:error]
  end

  test "for_ui returns empty array for nil or invalid structure" do
    assert_equal [], Dsl::TraceFormatter.for_ui(nil)
    assert_equal [], Dsl::TraceFormatter.for_ui("invalid")
  end

  test "preserves all trace steps even when large" do
    trace = (1..10).map do |i|
      {
        step: i,
        type: "ruby",
        code: "x" * 1000,
        input: ["y" * 1000],
        output: ["z" * 1000]
      }
    end

    formatted = Dsl::TraceFormatter.for_ui(trace)

    assert_equal 10, formatted.size
  end

  test "preserves last step containing error" do
    trace = (1..5).map do |i|
      { step: i, type: "ruby", code: "ok" }
    end

    trace << {
      step: 6,
      type: "ruby",
      code: "fail",
      error_class: "NoMethodError",
      error_message: "boom"
    }

    formatted = Dsl::TraceFormatter.for_ui(trace)

    last = formatted.last

    assert_equal 6, last[:step]
    assert_match /NoMethodError/, last[:error]
  end

  test "logs and skips malformed events without reducing valid count incorrectly" do
    trace = [
      { step: 1, type: "ruby", code: "ok" },
      "invalid_event",
      { step: 2, type: "xpath", code: "//a" }
    ]

    formatted = Dsl::TraceFormatter.for_ui(trace)

    assert_equal 2, formatted.size
  end

  test "for_session preserves all trace steps in compact events" do
    trace = (1..10).map do |i|
      {
        step: i,
        type: "ruby",
        code: "x" * 1000,
        input_preview: ["y" * 1000],
        output_preview: ["z" * 1000],
        url_before: "http://example.com",
        url_after: "http://example.com",
        duration_ms: 1.0
      }
    end

    compact = Dsl::TraceFormatter.for_session(trace).with_indifferent_access

    assert_equal 1, compact[:version]
    assert_equal 10, compact[:events].size
  end

  test "for_session keeps full error text and longer code on error step" do
    trace = [
      { step: 1, type: "ruby", code: "a" * 300 },
      {
        step: 2,
        type: "ruby",
        code: "b" * 300,
        error_class: "NoMethodError",
        error_message: "boom boom boom"
      }
    ]

    compact = Dsl::TraceFormatter.for_session(trace).with_indifferent_access
    normal = compact[:events].first.with_indifferent_access
    errored = compact[:events].second.with_indifferent_access

    assert_operator normal[:c].length, :<=, 83
    assert_operator errored[:c].length, :<=, 203
    assert_equal "NoMethodError: boom boom boom", errored[:e]
  end

  test "for_session deduplicates urls and stores index references" do
    trace = [
      { step: 1, type: "ruby", url_before: "http://example.com/a", url_after: "http://example.com/b" },
      { step: 2, type: "ruby", url_before: "http://example.com/a", url_after: "http://example.com/b" }
    ]

    compact = Dsl::TraceFormatter.for_session(trace).with_indifferent_access

    assert_equal ["http://example.com/a", "http://example.com/b"], compact[:urls]
    assert_equal 0, compact[:events].first.with_indifferent_access[:ub]
    assert_equal 1, compact[:events].first.with_indifferent_access[:ua]
    assert_equal 0, compact[:events].second.with_indifferent_access[:ub]
    assert_equal 1, compact[:events].second.with_indifferent_access[:ua]
  end

  test "for_session_v2 preserves all steps without loss" do
    trace = (1..20).map do |i|
      {
        step: i,
        type: "ruby",
        code: "x" * 1000,
        input_preview: ["y" * 1000],
        output_preview: ["z" * 1000],
        url_before: "http://example.com",
        url_after: "http://example.com",
        duration_ms: 1.0
      }
    end

    compact = Dsl::TraceFormatter.for_session_v2(trace).with_indifferent_access

    assert_equal 2, compact[:version]
    assert_equal 20, compact[:steps].size
  end

  test "for_session_v2 stores transition chain with initial state" do
    trace = [
      { step: 1, type: "ruby", input_preview: ["in-0"], output_preview: ["out-1"] },
      { step: 2, type: "ruby", input_preview: ["out-1"], output_preview: ["out-2"] }
    ]

    compact = Dsl::TraceFormatter.for_session_v2(trace).with_indifferent_access

    assert_match(/\A\[1 items: in-0\]\z/, compact[:initial].with_indifferent_access[:state])
    assert_match(/\A\[1 items: out-1\]\z/, compact[:steps].first.with_indifferent_access[:o])
    assert_match(/\A\[1 items: out-2\]\z/, compact[:steps].second.with_indifferent_access[:o])
  end

  test "for_session_v2 deduplicates urls and stores only url transitions" do
    trace = [
      { step: 1, type: "ruby", url_before: "http://example.com/a", url_after: "http://example.com/b" },
      { step: 2, type: "ruby", url_before: "http://example.com/b", url_after: "http://example.com/b" },
      { step: 3, type: "ruby", url_before: "http://example.com/b", url_after: "http://example.com/c" }
    ]

    compact = Dsl::TraceFormatter.for_session_v2(trace).with_indifferent_access
    steps = compact[:steps].map { |s| s.with_indifferent_access }

    assert_equal "http://example.com/a", compact[:initial].with_indifferent_access[:url]
    assert_equal ["http://example.com/b", "http://example.com/c"], compact[:urls]
    assert_equal 0, steps.first[:ua]
    assert_nil steps.second[:ua]
    assert_equal 1, steps.third[:ua]
  end

  test "for_session_v2 preserves error step details" do
    trace = [
      { step: 1, type: "ruby", code: "a" * 500 },
      {
        step: 2,
        type: "ruby",
        code: "f" * 500,
        error_class: "NoMethodError",
        error_message: "boom"
      }
    ]

    compact = Dsl::TraceFormatter.for_session_v2(trace).with_indifferent_access
    errored = compact[:steps].second.with_indifferent_access

    assert_equal 2, errored[:s]
    assert_match(/NoMethodError: boom/, errored[:e])
    assert errored[:c].present?
    assert_operator compact[:steps].first.with_indifferent_access[:c].length, :<=, 43
    assert_operator errored[:c].length, :<=, 123
  end

  test "for_session_v2 array summaries include sample content" do
    trace = [
      {
        step: 1,
        type: "ruby",
        input_preview: ["https://example.com/alpha/very/long/path", "2026-01-01", "ignored"],
        output_preview: ["https://example.com/beta/very/long/path", "ok", "ignored"]
      }
    ]

    compact = Dsl::TraceFormatter.for_session_v2(trace).with_indifferent_access
    initial_state = compact[:initial].with_indifferent_access[:state]
    output_state = compact[:steps].first.with_indifferent_access[:o]

    assert_match(/\A\[3 items: /, initial_state)
    assert_match(/https:\/\/example.com\/alpha/, initial_state)
    assert_match(/\A\[3 items: /, output_state)
    assert_match(/https:\/\/example.com\/beta/, output_state)
  end

  test "for_session_v2 preserves normalized probe payload" do
    trace = [
      { step: 1, type: "url", output_preview: [] },
      {
        step: 2,
        type: "xpath",
        output_preview: [],
        probe: {
          status: "ok",
          xpath: "//title",
          output: [nil, "Alpha", :beta, "Gamma", "Delta"]
        }
      }
    ]

    compact = Dsl::TraceFormatter.for_session_v2(trace).with_indifferent_access
    probe = compact[:steps].second.with_indifferent_access[:p].with_indifferent_access

    assert_equal "ok", probe[:st]
    assert_equal "//title", probe[:x]
    assert_equal ["Alpha", "beta", "Gamma"], probe[:o]
  end

  test "for_session_v2 includes full fields for warning and error severities" do
    trace = [
      { step: 1, type: "ruby", code: "ok", output_preview: ["ok"] },
      { step: 2, type: "ruby", code: "warn" * 60, output_preview: [], probe: { skipped: false, result: { status: "ok" } } },
      { step: 3, type: "ruby", code: "boom" * 60, output_preview: ["very long output " * 20], error_class: "RuntimeError", error_message: "boom" }
    ]

    compact = Dsl::TraceFormatter.for_session_v2(trace).with_indifferent_access
    ok_step = compact[:steps].first.with_indifferent_access
    warning_step = compact[:steps].second.with_indifferent_access
    error_step = compact[:steps].third.with_indifferent_access

    assert_nil ok_step[:cf]
    assert_nil ok_step[:of]
    assert warning_step[:cf].present?
    assert_equal "[]", warning_step[:of]
    assert error_step[:cf].present?
    assert error_step[:of].present?
  end

  test "for_session_v2 warning output full falls back to output limit" do
    trace = [
      {
        step: 1,
        type: "ruby",
        code: "warn",
        output_preview: ["x" * 400],
        wringer: { system_error: true }
      }
    ]

    compact = Dsl::TraceFormatter.for_session_v2(trace).with_indifferent_access
    step = compact[:steps].first.with_indifferent_access

    assert step[:o].present?
    assert step[:of].present?
    assert_equal step[:o], step[:of]
  end
end
