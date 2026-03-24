require "test_helper"

class Dsl::PipelineEvaluatorTest < ActiveSupport::TestCase
  test "evaluate returns metrics and diagnosis" do
    result = Dsl::PipelineEvaluator.evaluate(event: "uri1")

    assert result.is_a?(Hash)
    assert result[:metrics].is_a?(Hash)
    assert result[:diagnosis].is_a?(Hash)
    assert_includes result[:metrics].keys, :steps_count
    assert_includes result[:diagnosis].keys, :status
    assert_includes result[:diagnosis].keys, :category
  end

  test "diagnosis mapping is preserved from metrics" do
    result = Dsl::PipelineEvaluator.evaluate(event: "uri1")
    expected = Dsl::PipelineDiagnosis.new(
      metrics: result[:metrics],
      wringer: {
        unreachable: false,
        received_404: false,
        system_error: false,
        policy_action: nil
      }
    ).result

    assert_equal expected, result[:diagnosis]
  end

  test "does not execute dsl runner" do
    Dsl::DslAlgorithmRunner.expects(:new).never

    Dsl::PipelineEvaluator.evaluate(event: "uri1")
  end

  test "handles missing event pipeline data gracefully" do
    result = Dsl::PipelineEvaluator.evaluate(event: "missing-uri")

    assert_equal 0, result[:metrics][:steps_count]
    assert_equal :healthy, result[:diagnosis][:category]
  end

  test "wringer 404 forces wringer_failure diagnosis" do
    result = Dsl::PipelineEvaluator.evaluate(
      event: "uri1",
      wringer: {
        unreachable: false,
        received_404: true,
        system_error: false,
        policy_action: "abort_update"
      }
    )

    assert_equal :wringer_failure, result[:diagnosis][:category]
  end

  test "wringer unreachable forces wringer_failure diagnosis" do
    result = Dsl::PipelineEvaluator.evaluate(
      event: "uri1",
      wringer: {
        unreachable: true,
        received_404: false,
        system_error: false,
        policy_action: "abort_update"
      }
    )

    assert_equal :wringer_failure, result[:diagnosis][:category]
  end

  test "no wringer issues keeps diagnosis behavior unchanged" do
    baseline = Dsl::PipelineEvaluator.evaluate(event: "uri1")
    with_explicit_none = Dsl::PipelineEvaluator.evaluate(
      event: "uri1",
      wringer: {
        unreachable: false,
        received_404: false,
        system_error: false,
        policy_action: nil
      }
    )

    assert_equal baseline[:diagnosis], with_explicit_none[:diagnosis]
  end

  test "end-to-end wringer failure overrides navigation and extraction symptoms" do
    evaluator = Dsl::PipelineEvaluator.new(
      event: "uri1",
      wringer: {
        unreachable: true,
        received_404: false,
        system_error: false,
        policy_action: "abort_update"
      }
    )
    evaluator.stubs(:pipeline_steps).returns(
      [
        { step: 1, type: "url", output: nil },
        { step: 2, type: "xpath", output: [] }
      ]
    )

    result = evaluator.evaluate

    assert result[:metrics].is_a?(Hash)
    assert_equal true, result[:metrics][:suspicious_navigation]
    assert_equal :wringer_failure, result[:diagnosis][:category]
  end

  test "multi-step dsl is expanded into multiple pipeline steps" do
    evaluator = Dsl::PipelineEvaluator.new(event: "uri1")
    evaluator.stubs(:event_statements).returns([
      statement_like("xpath=//a;url='http://example.com';xpath=//b", "[]")
    ])

    steps = evaluator.send(:pipeline_steps)

    assert_equal 3, steps.size
    assert_equal %w[xpath url xpath], steps.map { |step| step[:type] }
  end

  test "step order is preserved from dsl sequence" do
    evaluator = Dsl::PipelineEvaluator.new(event: "uri1")
    evaluator.stubs(:event_statements).returns([
      statement_like("xpath=//a;ruby=$array.map(&:upcase);url='http://example.com';xpath=//b", "[]")
    ])

    steps = evaluator.send(:pipeline_steps)

    assert_equal %w[xpath ruby url xpath], steps.map { |step| step[:type] }
    assert_equal [1, 2, 3, 4], steps.map { |step| step[:step] }
  end

  test "mixed dsl operations are recognized as separate steps" do
    evaluator = Dsl::PipelineEvaluator.new(event: "uri1")
    evaluator.stubs(:event_statements).returns([
      statement_like("xpath=//a;ruby=$array.reject(&:blank?);url='http://example.com'", "[]")
    ])

    steps = evaluator.send(:pipeline_steps)

    assert_equal %w[xpath ruby url], steps.map { |step| step[:type] }
  end

  test "nil or empty dsl is handled safely as no steps" do
    evaluator = Dsl::PipelineEvaluator.new(event: "uri1")
    evaluator.stubs(:event_statements).returns([
      statement_like(nil, "[]"),
      statement_like("", "[]")
    ])

    assert_nothing_raised do
      assert_equal [], evaluator.send(:pipeline_steps)
    end
  end

  test "metrics reflect navigation for multi-step dsl with url step" do
    evaluator = Dsl::PipelineEvaluator.new(event: "uri1")
    evaluator.stubs(:event_statements).returns([
      statement_like("xpath=//a;url='http://example.com';xpath=//b", "[]")
    ])

    result = evaluator.evaluate

    assert_equal true, result[:metrics][:has_navigation]
    assert_equal true, result[:metrics][:suspicious_navigation]
  end

  test "single-step dsl remains backward compatible" do
    evaluator = Dsl::PipelineEvaluator.new(event: "uri1")
    evaluator.stubs(:event_statements).returns([
      statement_like("xpath=//a", "[]")
    ])

    steps = evaluator.send(:pipeline_steps)

    assert_equal 1, steps.size
    assert_equal "xpath", steps.first[:type]
    assert_equal 1, steps.first[:step]
  end

  test "xpath step has primitive extract" do
    steps = build_steps("xpath=//title")

    assert_equal :extract, steps.first[:primitive]
  end

  test "url step has primitive navigate" do
    steps = build_steps("url=http://example.com")

    assert_equal :navigate, steps.first[:primitive]
  end

  test "ruby step has primitive transform" do
    steps = build_steps("ruby=$array")

    assert_equal :transform, steps.first[:primitive]
  end

  test "if_xpath step has primitive branch" do
    steps = build_steps("if_xpath=//a")

    assert_equal :branch, steps.first[:primitive]
  end

  test "sparql step is transform primitive" do
    steps = build_steps("sparql={ ?s ?p ?o }")

    assert_equal :transform, steps.first[:primitive]
  end

  private

  def build_steps(algorithm_value, cache_value = "[]")
    evaluator = Dsl::PipelineEvaluator.new(event: "uri1")
    evaluator.stubs(:event_statements).returns([
      statement_like(algorithm_value, cache_value)
    ])

    evaluator.send(:pipeline_steps)
  end

  def statement_like(algorithm_value, cache_value)
    source = Struct.new(:algorithm_value).new(algorithm_value)
    Struct.new(:source, :cache).new(source, cache_value)
  end
end
