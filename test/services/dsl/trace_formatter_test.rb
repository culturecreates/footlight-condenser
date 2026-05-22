require "test_helper"

class Dsl::Tracing::TraceFormatterTest < ActiveSupport::TestCase
  test "for_ui truncates long strings" do
    formatted = Dsl::Tracing::TraceFormatter.for_ui([
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

    formatted = Dsl::Tracing::TraceFormatter.format_value(value)

    assert_match(/\A\[Array size=10, sample=/, formatted)
    assert_includes formatted, "1"
    assert_includes formatted, "5"
    refute_includes formatted, "6"
  end

  test "format_value converts exceptions to message" do
    formatted = Dsl::Tracing::TraceFormatter.format_value(StandardError.new("boom"))

    assert_equal "boom", formatted
  end

  test "format_value preserves nil" do
    assert_nil Dsl::Tracing::TraceFormatter.format_value(nil)
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

    formatted = Dsl::Tracing::TraceFormatter.for_ui(input)

    assert_equal 2, formatted.length
    assert_equal "xpath", formatted.first[:type]
    assert_match(/\A\[Array size=1, sample=\[\"one\"\]\]\z/, formatted.first[:input])
    assert_equal "RuntimeError: failed", formatted.second[:error]
  end

  test "for_ui returns empty array for nil or invalid structure" do
    assert_equal [], Dsl::Tracing::TraceFormatter.for_ui(nil)
    assert_equal [], Dsl::Tracing::TraceFormatter.for_ui("invalid")
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

    formatted = Dsl::Tracing::TraceFormatter.for_ui(trace)

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

    formatted = Dsl::Tracing::TraceFormatter.for_ui(trace)

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

    formatted = Dsl::Tracing::TraceFormatter.for_ui(trace)

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

    compact = Dsl::Tracing::TraceFormatter.for_session(trace).with_indifferent_access

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

    compact = Dsl::Tracing::TraceFormatter.for_session(trace).with_indifferent_access
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

    compact = Dsl::Tracing::TraceFormatter.for_session(trace).with_indifferent_access

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
        code: "x" * 12,
        input_preview: ["y" * 12],
        output_preview: ["z" * 12],
        url_before: "http://example.com",
        url_after: "http://example.com",
        duration_ms: 1.0
      }
    end

    compact = Dsl::Tracing::TraceFormatter.for_session_v2(trace).with_indifferent_access

    assert_equal 2, compact[:version]
    assert_equal 20, compact[:steps].size
  end

  test "for_session_v2 stores transition chain with initial state" do
    trace = [
      { step: 1, type: "ruby", input_preview: ["in-0"], output_preview: ["out-1"] },
      { step: 2, type: "ruby", input_preview: ["out-1"], output_preview: ["out-2"] }
    ]

    compact = Dsl::Tracing::TraceFormatter.for_session_v2(trace).with_indifferent_access

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

    compact = Dsl::Tracing::TraceFormatter.for_session_v2(trace).with_indifferent_access
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

    compact = Dsl::Tracing::TraceFormatter.for_session_v2(trace).with_indifferent_access
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

    compact = Dsl::Tracing::TraceFormatter.for_session_v2(trace).with_indifferent_access
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

    compact = Dsl::Tracing::TraceFormatter.for_session_v2(trace).with_indifferent_access
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

    compact = Dsl::Tracing::TraceFormatter.for_session_v2(trace).with_indifferent_access
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

    compact = Dsl::Tracing::TraceFormatter.for_session_v2(trace).with_indifferent_access
    step = compact[:steps].first.with_indifferent_access

    assert step[:o].present?
    assert step[:of].present?
    assert_equal step[:o], step[:of]
  end

  test "for_session_v2 enforces session budget after final fallback" do
    trace = (1..250).map do |i|
      {
        step: i,
        type: "ruby",
        code: "x" * 2000,
        input_preview: ["y" * 2000, "z" * 2000],
        output_preview: ["w" * 2000, "q" * 2000],
        error_class: "RuntimeError",
        error_message: "boom " * 80,
        wringer: {
          signals: {
            network_status: "failed",
            content_type: "html",
            primary_issue_key: "timeout",
            final_url: "https://example.org/" + ("deep/path/" * 30)
          },
          hints: Array.new(20) { "hint-" + ("very-long-" * 20) }
        }
      }
    end

    compact = Dsl::Tracing::TraceFormatter.for_session_v2(trace)

    assert_operator JSON.generate(compact).bytesize, :<=, Dsl::Tracing::TraceFormatter::MAX_SESSION_BYTES
    assert compact[:steps].present?
    assert_match(/Trace omitted|boom/, compact[:steps].first[:e].to_s)
  end

  test "for_session_v2 summarizes wringer diagnostics instead of copying full payloads" do
    trace = [
      {
        step: 1,
        type: "url",
        wringer: {
          policy_action: "abort_update",
          final_url: "https://example.org/final",
          redirect_chain: [
            "https://example.org/start",
            "https://example.org/final",
            "https://example.org/ignored"
          ],
          signals: {
            network_status: "ok",
            content_type: "html",
            blocking_issue_key: "redirect_to_listing",
            primary_issue_label: "Redirect to listing",
            fetch_backend: "phantomjs",
            fetched_body_state: "non_empty",
            stored_body_state: "not_stored",
            raw_html_blob: "<html>" + ("x" * 500) + "</html>",
            nested_payload: { giant: "y" * 500 }
          },
          hints: [
            "redirect_to_listing",
            { detail: "z" * 500 },
            "ignored-third-hint"
          ]
        }
      }
    ]

    compact = Dsl::Tracing::TraceFormatter.for_session_v2(trace).with_indifferent_access
    wringer = compact[:steps].first.with_indifferent_access[:w].with_indifferent_access
    signals = wringer[:s].with_indifferent_access

    assert_equal "https://example.org/final", wringer[:fu]
    assert_equal ["https://example.org/start", "https://example.org/final"], wringer[:rc]
    assert_equal "ok", signals[:network_status]
    assert_equal "html", signals[:content_type]
    assert_equal "redirect_to_listing", signals[:blocking_issue_key]
    assert_equal "Redirect to listing", signals[:primary_issue_label]
    assert_equal "phantomjs", signals[:fetch_backend]
    assert_equal "non_empty", signals[:fetched_body_state]
    assert_equal "not_stored", signals[:stored_body_state]
    refute signals.key?(:raw_html_blob)
    refute signals.key?(:nested_payload)
    assert_equal 2, wringer[:h].length
    assert_operator wringer[:h].first.length, :<=, 60
  end
end
