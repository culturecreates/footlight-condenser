require "test_helper"

class PreprocessingPoliciesControllerTest < ActionDispatch::IntegrationTest
  include PreprocessingTestSupport
  setup { build_preprocessing_fixture }

  test "index shows pilot links and current policy status" do
    get preprocessing_policies_path
    assert_response :success
    assert_includes response.body, @website.seedurl
    assert_select "a[href*='statement_id=646580']"
    get edit_preprocessing_policy_path(@policy)
    assert_response :success
    assert_includes response.body, "Current stored refresh"
    assert_includes response.body, "ruby=[&#39;mapped value&#39;]"
  end

  test "creates disabled draft and cannot accidentally enable on creation" do
    @policy.destroy!
    assert_difference("PreprocessingPolicy.count", 1) do
      post preprocessing_policies_path, params: { preprocessing_policy: { statement_id: @target.id, expected_seedurl: @website.seedurl, enabled: "1" } }
    end
    policy = PreprocessingPolicy.last
    assert_redirected_to edit_preprocessing_policy_path(policy)
    assert_not policy.enabled?
  end

  test "wrong website fails enrollment without creating a policy" do
    @policy.destroy!
    assert_no_difference("PreprocessingPolicy.count") do
      post preprocessing_policies_path, params: { preprocessing_policy: { statement_id: @target.id, expected_seedurl: "wrong" } }
    end
    assert_response :unprocessable_entity
  end

  test "invalid IDs remain visible on form and identity cannot be retargeted" do
    patch preprocessing_policy_path(@policy), params: { preprocessing_policy: { input_ids_text: "not-an-id" } }
    assert_response :unprocessable_entity
    assert_includes response.body, "not-an-id"
    patch preprocessing_policy_path(@policy), params: { preprocessing_policy: { statement_id: statements(:one).id, enabled: "0" } }
    assert_redirected_to edit_preprocessing_policy_path(@policy)
    assert_equal @target.id, @policy.reload.statement_id
  end

  test "policy issue kind and inspection link are available in shared monitoring feed" do
    Preprocessing::Monitor.call
    get monitoring_path(format: :json), params: { seedurl: @website.seedurl }
    issue = JSON.parse(response.body).fetch("issues").first
    assert_equal "stale_refresh", issue["kind"]
    assert_equal @policy.id, issue["preprocessing_policy_id"]
  end
  test "queue failure returns an actionable operator message and leaves a failed attempt" do
    RefreshPreprocessingStatementJob.expects(:perform_later).raises(StandardError, "queue unavailable")
    post run_preprocessing_policy_path(@policy)
    assert_redirected_to edit_preprocessing_policy_path(@policy)
    assert_includes flash[:alert], "Could not queue refresh"
    assert_equal "enqueue_failed", @policy.runs.last.status
  end

  test "policy page highlights stale inputs even after a successful refresh" do
    @input.update_columns(cache_refreshed: 4.days.ago)
    run = Preprocessing::Dispatcher.dispatch(@policy)
    Preprocessing::Runner.call(@policy.id, run.id)
    get edit_preprocessing_policy_path(@policy)
    assert_response :success
    assert_select "[role=alert]", text: /Stale inputs/
    assert_includes response.body, "succeeded"
    assert_includes response.body, "does not establish fresh inputs"
  end

  test "an existing flagged DSL error remains visible on its policy without duplication" do
    Monitoring::Recorder.failure(@target, error: "Mapping error already flagged", notify: "daily")
    @policy.update!(last_result: "failed", last_error: "Mapping error already flagged")
    Preprocessing::Monitor.evaluate(@policy)
    assert_not MonitoringIssue.open_issues.where(preprocessing_policy_id: @policy.id, kind: "preprocessing_failure").exists?
    get edit_preprocessing_policy_path(@policy)
    assert_select "[role=alert]", text: /Mapping error already flagged/
  end

end
