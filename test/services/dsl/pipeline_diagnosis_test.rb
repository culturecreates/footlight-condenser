require "test_helper"

class Dsl::PipelineDiagnosisTest < ActiveSupport::TestCase
  def base_metrics(overrides = {})
    {
      error_present: false,
      data_loss: false,
      extraction_empty: false,
      extraction_attempted: false,
      suspicious_navigation: false,
      failure_step: nil,
      recovered_after_loss: false,
      steps_count: 0,
      final_empty: false,
      has_navigation: false
    }.merge(overrides)
  end

  def base_wringer(overrides = {})
    {
      unreachable: false,
      received_404: false,
      system_error: false,
      policy_action: nil
    }.merge(overrides)
  end

  test "extraction failure without wringer signals" do
    diagnosis = Dsl::PipelineDiagnosis.new(
      metrics: base_metrics(extraction_attempted: true, extraction_empty: true),
      wringer: base_wringer
    ).result

    assert_equal :warning, diagnosis[:status]
    assert_equal :extraction_failure, diagnosis[:category]
    assert_equal :check_xpath, diagnosis[:suggested_action]
  end

  test "suspicious navigation without wringer unreachable" do
    diagnosis = Dsl::PipelineDiagnosis.new(
      metrics: base_metrics(suspicious_navigation: true, has_navigation: true, extraction_attempted: true),
      wringer: base_wringer(unreachable: false)
    ).result

    assert_equal :warning, diagnosis[:status]
    assert_equal :navigation_failure, diagnosis[:category]
    assert_equal :check_url, diagnosis[:suggested_action]
  end

  test "suspicious navigation with wringer unreachable becomes wringer failure" do
    diagnosis = Dsl::PipelineDiagnosis.new(
      metrics: base_metrics(suspicious_navigation: true, has_navigation: true, extraction_attempted: true),
      wringer: base_wringer(unreachable: true)
    ).result

    assert_equal :error, diagnosis[:status]
    assert_equal :wringer_failure, diagnosis[:category]
    assert_equal :retry, diagnosis[:suggested_action]
  end

  test "wringer 404 diagnosis" do
    diagnosis = Dsl::PipelineDiagnosis.new(
      metrics: base_metrics,
      wringer: base_wringer(received_404: true)
    ).result

    assert_equal :error, diagnosis[:status]
    assert_equal :wringer_failure, diagnosis[:category]
    assert_equal :check_url, diagnosis[:suggested_action]
  end

  test "data loss after extraction diagnosis" do
    diagnosis = Dsl::PipelineDiagnosis.new(
      metrics: base_metrics(data_loss: true, extraction_attempted: true),
      wringer: base_wringer
    ).result

    assert_equal :warning, diagnosis[:status]
    assert_equal :data_loss, diagnosis[:category]
    assert_equal :investigate, diagnosis[:suggested_action]
  end

  test "error present diagnosis" do
    diagnosis = Dsl::PipelineDiagnosis.new(
      metrics: base_metrics(error_present: true, failure_step: 4, data_loss: true),
      wringer: base_wringer(unreachable: true)
    ).result

    assert_equal :error, diagnosis[:status]
    assert_equal :error, diagnosis[:category]
    assert_equal :investigate, diagnosis[:suggested_action]
  end

  test "healthy pipeline diagnosis" do
    diagnosis = Dsl::PipelineDiagnosis.new(
      metrics: base_metrics,
      wringer: base_wringer
    ).result

    assert_equal :ok, diagnosis[:status]
    assert_equal :healthy, diagnosis[:category]
  end

  test "healthy diagnosis has no action" do
    diagnosis = Dsl::PipelineDiagnosis.new(
      metrics: base_metrics,
      wringer: base_wringer
    ).result

    assert_equal :none, diagnosis[:suggested_action]
  end

  test "priority data loss overrides extraction failure" do
    diagnosis = Dsl::PipelineDiagnosis.new(
      metrics: base_metrics(
        data_loss: true,
        extraction_attempted: true,
        extraction_empty: true
      ),
      wringer: base_wringer
    ).result

    assert_equal :data_loss, diagnosis[:category]
  end

  test "priority wringer failure overrides navigation and extraction" do
    diagnosis = Dsl::PipelineDiagnosis.new(
      metrics: base_metrics(
        suspicious_navigation: true,
        extraction_attempted: true,
        extraction_empty: true
      ),
      wringer: base_wringer(system_error: true)
    ).result

    assert_equal :wringer_failure, diagnosis[:category]
  end

  test "priority error overrides everything else" do
    diagnosis = Dsl::PipelineDiagnosis.new(
      metrics: base_metrics(
        error_present: true,
        data_loss: true,
        suspicious_navigation: true,
        extraction_attempted: true,
        extraction_empty: true
      ),
      wringer: base_wringer(unreachable: true, received_404: true, system_error: true)
    ).result

    assert_equal :error, diagnosis[:category]
  end
end
