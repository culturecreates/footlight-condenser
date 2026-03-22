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
end
