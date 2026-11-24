require "test_helper"

class PreprocessingRunnerTest < ActiveJob::TestCase
  include PreprocessingTestSupport
  setup { build_preprocessing_fixture }

  test "real DSL saves one exact statement and unchanged output still refreshes successfully" do
    run = queued_preprocessing_run
    other = statements(:one)
    other.webpage.update_columns(url: @derived.url)
    other_before = other.cache
    Preprocessing::Runner.call(@policy.id, run.id)
    assert_equal "succeeded", run.reload.status
    assert_equal "mapped value", @target.reload.cache
    assert_equal other_before, other.reload.cache
    assert_equal @target.cache_refreshed, @policy.reload.last_success_at
    assert_nil @policy.active_run_id
    assert_operator @policy.next_due_at, :>, 11.hours.from_now
    changed = @target.cache_changed
    second = Preprocessing::Dispatcher.dispatch(@policy, force: true)
    Preprocessing::Runner.call(@policy.id, second.id)
    assert_equal "succeeded", second.reload.status
    assert_equal changed, @target.reload.cache_changed
  end

  test "abort preserves good cache and a failure does not prevent a different policy from running" do
    @source.update!(algorithm_value: "ruby=['abort_update', {error: 'Mapping unavailable'}]")
    run = queued_preprocessing_run
    Preprocessing::Runner.call(@policy.id, run.id)
    assert_equal "failed", run.reload.status
    assert_equal "old value", @target.reload.cache
    assert_nil @policy.reload.last_success_at
    assert_operator @policy.next_due_at, :<=, 1.hour.from_now
    assert MonitoringIssue.open_issues.where(kind: "preprocessing_failure", preprocessing_policy_id: @policy.id).exists?
    source = Source.create!(website: @website, property: @property, language: "en", algorithm_value: "ruby=['other mapping']")
    target = Statement.create!(webpage: @derived, source: source, cache: "old", status: "updated", manual: false)
    other = PreprocessingPolicy.create!(statement_id: target.id, expected_seedurl: @website.seedurl, enabled: true,
      inputs_verified: true, input_statement_ids: [@input.id])
    other_run = Preprocessing::Dispatcher.dispatch(other)
    Preprocessing::Runner.call(other.id, other_run.id)
    assert_equal "succeeded", other_run.reload.status
    assert_equal "other mapping", target.reload.cache
  end

  test "blank preserved value and helper returning no save never count as success" do
    @source.update!(algorithm_value: "ruby=[]")
    run = queued_preprocessing_run
    Preprocessing::Runner.call(@policy.id, run.id)
    assert_equal "failed", run.reload.status
    @policy.reload.update!(next_due_at: nil)
    helper = mock
    helper.expects(:refresh_statement_helper).returns(errors: [], saved: false)
    run = queued_preprocessing_run
    Preprocessing::Runner.call(@policy.id, run.id, helper: helper)
    assert_equal "failed", run.reload.status
    assert_includes run.error, "without saving"
    assert_equal "old value", @target.reload.cache
  end

  test "manual overrides are protected even while awaiting review" do
    @target.update_columns(manual: true, status: "initial")
    run = queued_preprocessing_run
    Preprocessing::Runner.call(@policy.id, run.id)
    assert_equal "failed", run.reload.status
    assert_includes run.error, Statement::MANUAL_REFRESH_BLOCKED
    assert_equal "old value", @target.reload.cache
  end

  test "changed queued configuration skips its old job" do
    run = queued_preprocessing_run
    @policy.update!(interval_hours: 24)
    helper = mock
    helper.expects(:refresh_statement_helper).never
    Preprocessing::Runner.call(@policy.id, run.id, helper: helper)
    assert_equal "skipped", run.reload.status
    assert_nil @policy.reload.active_run_id
  end

  test "superseded configuration rolls back the statement result" do
    run = queued_preprocessing_run
    digest = @policy.configuration_digest
    PreprocessingPolicy.any_instance.stubs(:configuration_digest).returns(digest, "superseded")
    Preprocessing::Runner.call(@policy.id, run.id)
    assert_equal "old value", @target.reload.cache
    assert_equal "skipped", run.reload.status
    assert_nil @policy.reload.last_success_at
  end

  test "changed ownership is detected before any DSL runs" do
    run = queued_preprocessing_run
    @derived.update_columns(website_id: websites(:two).id)
    helper = mock
    helper.expects(:refresh_statement_helper).never
    Preprocessing::Runner.call(@policy.id, run.id, helper: helper)
    assert_equal "failed", run.reload.status
    assert_includes run.error, "identity changed"
  end

  test "timeout is recorded and releases lease without damaging good cache" do
    run = queued_preprocessing_run
    helper = mock
    helper.expects(:refresh_statement_helper).raises(Timeout::Error, "execution expired")
    Preprocessing::Runner.call(@policy.id, run.id, helper: helper)
    assert_equal "failed", run.reload.status
    assert_nil @policy.reload.active_run_id
    assert_equal "old value", @target.reload.cache
  end
  test "queued job path completes and a duplicate delivery does not repeat DSL execution" do
    perform_enqueued_jobs(only: RefreshPreprocessingStatementJob) { Preprocessing::Dispatcher.call }
    run = @policy.runs.last
    assert_equal "succeeded", run.status
    helper = mock("completed run")
    helper.expects(:refresh_statement_helper).never
    Preprocessing::Runner.call(@policy.id, run.id, helper: helper)
    assert_equal 1, @policy.runs.count
  end

  test "successive scheduler ticks record stale input and recover from a failed refresh when retry is due" do
    start = Time.current.change(usec: 0)
    @policy.update!(interval_hours: 12, stale_after_hours: 12)
    @input.update_columns(cache_refreshed: start)
    @source.update!(algorithm_value: "ruby=Statement.find(#{@input.id}).cache.then { |value| value == 'unavailable' ? ['abort_update', {error: 'Mapping unavailable'}] : [value] }")
    tick = -> { perform_enqueued_jobs(only: RefreshPreprocessingStatementJob) { Preprocessing::Dispatcher.call } }

    travel_to(start) { tick.call }
    assert_equal "input", @target.reload.cache
    assert_equal start, @target.cache_refreshed
    original_change = @target.cache_changed

    travel_to(start + 1.hour) { tick.call }
    assert_equal 1, @policy.runs.count

    failed_at = start + 13.hours
    travel_to(failed_at) do
      @input.update!(cache: "unavailable")
      tick.call
      assert_equal "failed", @policy.runs.order(:id).last.status
      assert_equal "input", @target.reload.cache
      assert_equal start, @target.cache_refreshed
      assert_equal failed_at + 1.hour, @policy.reload.next_due_at
      assert_includes @policy.monitoring_issues.pluck(:kind), "stale_inputs"
      assert_includes @policy.monitoring_issues.pluck(:kind), "preprocessing_failure"
    end

    travel_to(failed_at + 1.hour) do
      @input.update!(cache: "input", cache_refreshed: Time.current)
      tick.call
      assert_equal %w[succeeded failed succeeded], @policy.runs.order(:id).pluck(:status)
      assert_equal Time.current, @target.reload.cache_refreshed
      assert_equal original_change, @target.cache_changed
      assert_empty @policy.monitoring_issues
    end
  end

end
