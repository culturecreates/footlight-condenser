require "test_helper"

class Dsl::PipelineInterpreterTest < ActiveSupport::TestCase
  test "pipeline interpreter loads without raising" do
    assert_nothing_raised do
      Dsl::PipelineInterpreter.new([])
    end
  end

  test "pipeline interpreter metrics can be called safely" do
    assert_nothing_raised do
      Dsl::PipelineInterpreter.new([]).metrics
    end
  end

  test "metrics exposes expected keys and base counts" do
    steps = [
      { step: 1, type: "xpath", output: ["a"] },
      { step: 2, type: "ruby", output: ["b"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal(
      [
        :error_present,
        :data_loss,
        :extraction_empty,
        :extraction_attempted,
        :suspicious_navigation,
        :failure_step,
        :recovered_after_loss,
        :steps_count,
        :final_empty,
        :has_navigation
      ],
      metrics.keys
    )
    assert_equal 2, metrics[:steps_count]
    assert_equal false, metrics[:has_navigation]
  end

  test "error_present is true when any step contains error" do
    steps = [
      { step: 1, type: "xpath", output: ["a"] },
      { step: 2, type: "ruby", output: [], error: "boom" }
    ]

    assert_equal true, Dsl::PipelineInterpreter.new(steps).metrics[:error_present]
  end

  test "data_loss is true when non-empty output becomes empty" do
    steps = [
      { step: 1, type: "xpath", output: ["a"] },
      { step: 2, type: "ruby", output: [] }
    ]

    assert_equal true, Dsl::PipelineInterpreter.new(steps).metrics[:data_loss]
  end

  test "data_loss is true when output array shrinks" do
    steps = [
      { step: 10, type: "xpath", output: %w[a b c] },
      { step: 42, type: "ruby", output: ["a"] }
    ]

    assert_equal true, Dsl::PipelineInterpreter.new(steps).metrics[:data_loss]
  end

  test "extraction_empty follows final output when xpath-like steps are empty but final output is present" do
    steps = [
      { step: 1, type: "xpath", output: [] },
      { step: 2, type: "if_xpath", output: nil },
      { step: 3, type: "ruby", output: ["value"] }
    ]

    assert_equal false, Dsl::PipelineInterpreter.new(steps).metrics[:extraction_empty]
  end

  test "failure_step prefers first error step over data-loss step" do
    steps = [
      { step: 1, type: "xpath", output: ["a"] },
      { step: 2, type: "ruby", output: [], error: "boom" },
      { step: 3, type: "ruby", output: [] }
    ]

    assert_equal 2, Dsl::PipelineInterpreter.new(steps).metrics[:failure_step]
  end

  test "failure_step is nil when data loss is recovered and final output is present" do
    steps = [
      { step: 1, type: "xpath", output: ["a"] },
      { step: 2, type: "ruby", output: [] },
      { step: 3, type: "ruby", output: ["recovered"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:data_loss]
    assert_equal false, metrics[:suspicious_navigation]
    assert_nil metrics[:failure_step]
  end

  test "failure_step returns last non-sequential step number for unresolved final failure" do
    steps = [
      { step: 10, type: "xpath", output: ["a"] },
      { step: 42, type: "ruby", output: [] },
      { step: 90, type: "ruby", output: [] }
    ]

    assert_equal 90, Dsl::PipelineInterpreter.new(steps).metrics[:failure_step]
  end

  test "failure_step is nil when failing step has no step number" do
    steps = [
      { step: 10, type: "xpath", output: ["a"] },
      { type: "ruby", output: [] }
    ]

    assert_nil Dsl::PipelineInterpreter.new(steps).metrics[:failure_step]
  end

  test "failure_step is nil when empty extraction is later recovered" do
    steps = [
      { step: 1, type: "xpath", output: [] },
      { step: 2, type: "url", output: ["..."] },
      { step: 3, type: "xpath", output: ["valid"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_nil metrics[:failure_step]
  end

  test "failure_step is last step when final output is empty" do
    steps = [
      { step: 1, type: "xpath", output: [] },
      { step: 2, type: "url", output: ["..."] },
      { step: 3, type: "xpath", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal 3, metrics[:failure_step]
  end

  test "failure_step is last step when ruby clears output" do
    steps = [
      { step: 1, type: "xpath", output: ["valid"] },
      { step: 2, type: "ruby", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal 2, metrics[:failure_step]
  end

  test "failure_step prioritizes error over final output" do
    steps = [
      { step: 1, type: "xpath", output: ["valid"] },
      { step: 2, type: "ruby", error: "boom", output: nil }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal 2, metrics[:failure_step]
  end

  test "failure_step is nil when no extraction attempted" do
    steps = [
      { step: 1, type: "ruby", output: ["value"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_nil metrics[:failure_step]
  end

  test "complex pipeline uses final output as truth" do
    steps = [
      { step: 1, type: "xpath", output: [] },
      { step: 2, type: "ruby", output: ["transformed"] },
      { step: 3, type: "xpath", output: [] },
      { step: 4, type: "ruby", output: ["final"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_nil metrics[:failure_step]
  end

  test "failure_step does not alter suspicious navigation or data loss signals" do
    steps = [
      { step: 1, type: "url", output: nil },
      { step: 2, type: "xpath", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal false, metrics[:data_loss]
    assert_equal true, metrics[:suspicious_navigation]
    assert_equal 2, metrics[:failure_step]
  end

  test "recovered_after_loss is true when data appears after a loss" do
    steps = [
      { step: 1, type: "xpath", output: ["a"] },
      { step: 2, type: "ruby", output: [] },
      { step: 3, type: "ruby", output: ["c"] }
    ]

    assert_equal true, Dsl::PipelineInterpreter.new(steps).metrics[:recovered_after_loss]
  end

  test "recovered_after_loss is true for partial loss followed by growth" do
    steps = [
      { step: 1, type: "xpath", output: %w[a b c] },
      { step: 2, type: "ruby", output: ["a"] },
      { step: 3, type: "ruby", output: %w[a b] }
    ]

    assert_equal true, Dsl::PipelineInterpreter.new(steps).metrics[:recovered_after_loss]
  end

  test "recovered_after_loss is true for full loss followed by non-blank output" do
    steps = [
      { step: 1, type: "xpath", output: ["a"] },
      { step: 2, type: "ruby", output: "" },
      { step: 3, type: "ruby", output: ["x"] }
    ]

    assert_equal true, Dsl::PipelineInterpreter.new(steps).metrics[:recovered_after_loss]
  end

  test "final_empty tracks whether last output is blank" do
    steps = [
      { step: 1, type: "xpath", output: ["a"] },
      { step: 2, type: "ruby", output: [] }
    ]

    assert_equal true, Dsl::PipelineInterpreter.new(steps).metrics[:final_empty]
  end

  test "has_navigation is true when url step exists" do
    steps = [
      { step: 1, type: "url", output: nil },
      { step: 2, type: "xpath", output: ["a"] }
    ]

    assert_equal true, Dsl::PipelineInterpreter.new(steps).metrics[:has_navigation]
  end

  test "has_navigation detects variant url-like step types" do
    steps = [
      { step: 1, type: "pre_url_cleanup", output: nil },
      { step: 2, type: "xpath", output: ["a"] }
    ]

    assert_equal true, Dsl::PipelineInterpreter.new(steps).metrics[:has_navigation]
  end

  test "extraction_empty ignores xpath steps that happen after navigation" do
    steps = [
      { step: 1, type: "xpath", output: [] },
      { step: 2, type: "url", output: nil },
      { step: 3, type: "xpath", output: ["late-xpath"] },
      { step: 4, type: "ruby", output: ["done"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:extraction_attempted]
    assert_equal false, metrics[:extraction_empty]
  end

  test "extraction_attempted is false when no xpath-like step exists" do
    steps = [
      { step: 1, type: "url", output: nil },
      { step: 2, type: "ruby", output: ["a"] }
    ]

    assert_equal false, Dsl::PipelineInterpreter.new(steps).metrics[:extraction_attempted]
  end

  test "extraction_attempted uses primitive not type string" do
    steps = [
      { step: 1, primitive: :extract, output: ["data"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:extraction_attempted]
  end

  test "has_navigation uses primitive" do
    steps = [
      { step: 1, primitive: :navigate, output: ["url"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:has_navigation]
  end

  test "primitive fallback works when missing" do
    steps = [
      { step: 1, type: "xpath", output: ["data"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:extraction_attempted]
  end

  test "consistency keeps error_present coherent with failure_step when step number exists" do
    steps = [
      { step: 100, type: "ruby", output: ["a"], error: "boom" }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:error_present]
    assert_equal 100, metrics[:failure_step]
  end

  test "error_present remains true when error step has no number and failure_step is nil" do
    steps = [
      { step: 1, type: "xpath", output: ["a"] },
      { type: "ruby", output: ["b"], error: "boom" }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:error_present]
    assert_nil metrics[:failure_step]
  end

  test "data_loss remains true when loss step has no number and failure_step is nil" do
    steps = [
      { step: 1, type: "xpath", output: ["a"] },
      { type: "ruby", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:data_loss]
    assert_nil metrics[:failure_step]
  end

  test "truth signals are preserved when error step number is missing and later loss exists" do
    steps = [
      { step: 1, type: "xpath", output: ["a"] },
      { type: "ruby", output: ["a"], error: "boom" },
      { step: 3, type: "ruby", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:error_present]
    assert_equal true, metrics[:data_loss]
    assert_nil metrics[:failure_step]
  end

  test "xpath then ruby then xpath ignores second xpath in extraction_empty" do
    steps = [
      { step: 1, type: "xpath", output: [] },
      { step: 2, type: "ruby", output: ["transformed"] },
      { step: 3, type: "xpath", output: ["late"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:extraction_attempted]
    assert_equal false, metrics[:extraction_empty]
  end

  test "xpath after url is considered extraction" do
    steps = [
      { step: 1, type: "url", output: nil },
      { step: 2, type: "xpath", output: ["post-nav-data"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:extraction_attempted]
    assert_equal false, metrics[:extraction_empty]
  end

  test "xpath after url blank output sets extraction_empty true" do
    steps = [
      { step: 1, type: "url", output: nil },
      { step: 2, type: "xpath", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:extraction_attempted]
    assert_equal true, metrics[:extraction_empty]
  end

  test "mixed pre and post navigation extraction is evaluated together" do
    steps = [
      { step: 1, type: "xpath", output: [] },
      { step: 2, type: "url", output: nil },
      { step: 3, type: "xpath", output: ["post-nav-data"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:extraction_attempted]
    assert_equal false, metrics[:extraction_empty]
  end

  test "extraction_empty is false when xpath is empty but final ruby output is present" do
    steps = [
      { step: 1, type: "xpath", output: [] },
      { step: 2, type: "ruby", output: ["valid"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal false, metrics[:extraction_empty]
  end

  test "extraction_empty is true when xpath steps are empty and final output is empty" do
    steps = [
      { step: 1, type: "xpath", output: [] },
      { step: 2, type: "xpath", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:extraction_empty]
  end

  test "extraction_empty is true when xpath has valid output but final ruby output is empty" do
    steps = [
      { step: 1, type: "xpath", output: ["valid"] },
      { step: 2, type: "ruby", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:extraction_empty]
  end

  test "extraction_empty follows final output in complex pipeline" do
    steps = [
      { step: 1, type: "xpath", output: [] },
      { step: 2, type: "ruby", output: ["mid"] },
      { step: 3, type: "xpath", output: ["x"] },
      { step: 4, type: "ruby", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:extraction_empty]
  end

  test "no xpath means extraction not attempted and not empty" do
    steps = [
      { step: 1, type: "url", output: nil },
      { step: 2, type: "ruby", output: ["a"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal false, metrics[:extraction_attempted]
    assert_equal false, metrics[:extraction_empty]
  end

  test "xpath all blank with final non-blank output means extraction attempted and not empty" do
    steps = [
      { step: 1, type: "xpath", output: nil },
      { step: 2, type: "if_xpath", output: [] },
      { step: 3, type: "ruby", output: ["done"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:extraction_attempted]
    assert_equal false, metrics[:extraction_empty]
  end

  test "no loss when outputs change but remain non-blank with same size" do
    steps = [
      { step: 1, type: "xpath", output: ["a"] },
      { step: 2, type: "ruby", output: ["b"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal false, metrics[:data_loss]
    assert_equal false, metrics[:recovered_after_loss]
  end

  test "no recovery when there is full loss and no later output" do
    steps = [
      { step: 1, type: "xpath", output: ["a"] },
      { step: 2, type: "ruby", output: [] }
    ]

    assert_equal false, Dsl::PipelineInterpreter.new(steps).metrics[:recovered_after_loss]
  end

  test "normalization handles nil blank array and blank string transitions safely" do
    steps = [
      { step: 1, type: "ruby", output: nil },
      { step: 2, type: "ruby", output: [] },
      { step: 3, type: "ruby", output: "" }
    ]

    metrics = nil
    assert_nothing_raised do
      metrics = Dsl::PipelineInterpreter.new(steps).metrics
    end

    assert_equal false, metrics[:data_loss]
    assert_equal false, metrics[:recovered_after_loss]
    assert_equal true, metrics[:final_empty]
  end

  test "arrays with nil entries do not cause false data loss" do
    steps = [
      { step: 1, type: "ruby", output: [nil, "a"] },
      { step: 2, type: "ruby", output: ["a"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics
    assert_equal false, metrics[:data_loss]
  end

  test "has_navigation is true for post_url_transform variant" do
    steps = [
      { step: 1, type: "post_url_transform", output: nil },
      { step: 2, type: "ruby", output: ["a"] }
    ]

    assert_equal true, Dsl::PipelineInterpreter.new(steps).metrics[:has_navigation]
  end

  test "metrics does not crash on malformed steps" do
    steps = [
      nil,
      "broken-step",
      123,
      { step: 3, type: "xpath", output: "" },
      { step: 4 },
      { step: 4, type: "ruby", output: ["alive"] },
      { step: 6, type: "ruby", output: [] }
    ]

    metrics = nil
    assert_nothing_raised do
      metrics = Dsl::PipelineInterpreter.new(steps).metrics
    end

    assert_equal 7, metrics[:steps_count]
    assert_equal true, metrics[:data_loss]
    assert_equal 6, metrics[:failure_step]
  end

  test "metrics is idempotent for same input" do
    steps = [
      { step: 1, type: "xpath", output: %w[a b] },
      { step: 2, type: "ruby", output: ["a"] },
      { step: 3, type: "ruby", output: %w[a c] }
    ]

    interpreter = Dsl::PipelineInterpreter.new(steps)
    first = interpreter.metrics
    second = interpreter.metrics
    third = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal first, second
    assert_equal first, third
  end

  test "failure_step points to first error when multiple errors exist" do
    steps = [
      { step: 5, type: "ruby", output: ["a"], error: "first" },
      { step: 7, type: "ruby", output: ["b"], error: "second" }
    ]

    assert_equal 5, Dsl::PipelineInterpreter.new(steps).metrics[:failure_step]
  end

  test "failure_step is nil when only ruby steps exist even with losses" do
    steps = [
      { step: 1, type: "ruby", output: %w[a b c] },
      { step: 4, type: "ruby", output: ["a"] },
      { step: 9, type: "ruby", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:data_loss]
    assert_equal false, metrics[:extraction_attempted]
    assert_nil metrics[:failure_step]
  end

  test "extraction_empty cannot be true when extraction_attempted is false" do
    steps = [
      { step: 1, type: "url", output: nil },
      { step: 2, type: "ruby", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics
    assert_equal false, metrics[:extraction_attempted]
    assert_equal false, metrics[:extraction_empty]
  end

  test "recovered_after_loss cannot be true when data_loss is false" do
    steps = [
      { step: 1, type: "ruby", output: ["a"] },
      { step: 2, type: "ruby", output: ["b"] },
      { step: 3, type: "ruby", output: ["c"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics
    assert_equal false, metrics[:data_loss]
    assert_equal false, metrics[:recovered_after_loss]
  end

  test "probe metadata does not affect interpreter metrics or diagnosis" do
    base_steps = [
      { step: 1, type: "url", output: nil },
      { step: 2, type: "xpath", output: [] }
    ]
    probe_steps = [
      { step: 1, type: "url", output: nil },
      {
        step: 2,
        type: "xpath",
        output: [],
        probe: { status: "ok", xpath: "//title", output: ["Probe Title"] }
      }
    ]

    metrics_without_probe = Dsl::PipelineInterpreter.new(base_steps).metrics
    metrics_with_probe = Dsl::PipelineInterpreter.new(probe_steps).metrics

    assert_equal metrics_without_probe, metrics_with_probe

    wringer = { unreachable: false, received_404: false, system_error: false, policy_action: nil }
    diagnosis_without_probe = Dsl::PipelineDiagnosis.new(metrics: metrics_without_probe, wringer: wringer).result
    diagnosis_with_probe = Dsl::PipelineDiagnosis.new(metrics: metrics_with_probe, wringer: wringer).result

    assert_equal diagnosis_without_probe, diagnosis_with_probe
  end

  test "final_empty is based on last output only" do
    steps = [
      { step: 1, type: "ruby", output: ["a"] },
      { step: 2, type: "ruby", output: [] },
      { step: 3, type: "ruby", output: ["z"] }
    ]

    assert_equal false, Dsl::PipelineInterpreter.new(steps).metrics[:final_empty]
  end

  test "suspicious_navigation is true when navigation followed by empty extraction" do
    steps = [
      { step: 1, type: "url", output: nil },
      { step: 2, type: "xpath", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:suspicious_navigation]
  end

  test "suspicious_navigation is false when navigation followed by successful extraction" do
    steps = [
      { step: 1, type: "url", output: nil },
      { step: 2, type: "xpath", output: ["data"] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal false, metrics[:suspicious_navigation]
  end

  test "suspicious_navigation is false when no navigation occurs" do
    steps = [
      { step: 1, type: "xpath", output: [] },
      { step: 2, type: "ruby", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal false, metrics[:suspicious_navigation]
  end

  test "suspicious_navigation ignores xpath outside extraction phase" do
    steps = [
      { step: 1, type: "url", output: nil },
      { step: 2, type: "ruby", output: ["prep"] },
      { step: 3, type: "xpath", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal false, metrics[:suspicious_navigation]
  end

  test "suspicious_navigation detects url-like step types" do
    steps = [
      { step: 1, type: "post_url_transform", output: nil },
      { step: 2, type: "xpath", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:suspicious_navigation]
  end

  test "suspicious_navigation cannot be true when has_navigation is false" do
    steps = [
      { step: 1, type: "xpath", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal false, metrics[:has_navigation]
    assert_equal false, metrics[:suspicious_navigation]
  end

  test "suspicious_navigation true implies navigation and extraction were attempted" do
    steps = [
      { step: 1, type: "url", output: nil },
      { step: 2, type: "xpath", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:suspicious_navigation]
    assert_equal true, metrics[:has_navigation]
    assert_equal true, metrics[:extraction_attempted]
  end

  test "suspicious_navigation does not force data_loss to true by itself" do
    steps = [
      { step: 1, type: "url", output: nil },
      { step: 2, type: "xpath", output: [] }
    ]

    metrics = Dsl::PipelineInterpreter.new(steps).metrics

    assert_equal true, metrics[:suspicious_navigation]
    assert_equal false, metrics[:data_loss]
  end


end
