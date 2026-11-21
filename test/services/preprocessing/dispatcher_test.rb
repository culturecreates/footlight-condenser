require "test_helper"

class PreprocessingDispatcherTest < ActiveJob::TestCase
  include PreprocessingTestSupport
  setup { build_preprocessing_fixture }

  test "queues each due target once and leaves disabled and ordinary site jobs alone" do
    RefreshWebpageJob.expects(:perform_later).never
    ExportToArtsdataJob.expects(:perform_later).never
    assert_enqueued_jobs 1, only: RefreshPreprocessingStatementJob do
      Preprocessing::Dispatcher.call
      Preprocessing::Dispatcher.call
    end
    assert_equal 1, @policy.runs.count
    @policy.update!(enabled: false)
    assert_no_enqueued_jobs(only: RefreshPreprocessingStatementJob) { Preprocessing::Dispatcher.call }
  end

  test "expired queue lease is recovered and its stale delivery cannot execute" do
    old = queued_preprocessing_run
    @policy.update_columns(lease_expires_at: 1.minute.ago)
    new_run = Preprocessing::Dispatcher.dispatch(@policy)
    assert_equal "interrupted", old.reload.status
    assert_equal new_run.id, @policy.reload.active_run_id
    helper = mock("stale job must not refresh")
    helper.expects(:refresh_statement_helper).never
    Preprocessing::Runner.call(@policy.id, old.id, helper: helper)
    assert_equal new_run.id, @policy.reload.active_run_id
  end

  test "enqueue failure releases claim and remains retryable" do
    RefreshPreprocessingStatementJob.expects(:perform_later).raises(StandardError, "queue unavailable")
    assert_raises(StandardError) { queued_preprocessing_run }
    assert_nil @policy.reload.active_run_id
    assert_equal "enqueue_failed", @policy.runs.last.status
    assert_equal "failed", @policy.last_result
  end

  test "future successful due time is respected" do
    @policy.update!(next_due_at: 10.hours.from_now)
    assert_no_enqueued_jobs(only: RefreshPreprocessingStatementJob) { Preprocessing::Dispatcher.call }
  end
  test "one enqueue failure does not strand another eligible policy" do
    source = Source.create!(website: @website, property: @property, algorithm_value: "ruby=['another']")
    target = Statement.create!(source: source, webpage: @derived, cache: "old", status: "updated", manual: false)
    other = PreprocessingPolicy.create!(statement_id: target.id, expected_seedurl: @website.seedurl, enabled: true,
      inputs_verified: true, input_statement_ids: [@input.id])
    RefreshPreprocessingStatementJob.expects(:perform_later).with(@policy.id, anything).raises(StandardError, "queue failed")
    RefreshPreprocessingStatementJob.expects(:perform_later).with(other.id, anything).returns(stub(job_id: "queued"))
    Preprocessing::Dispatcher.call
    assert_equal "failed", @policy.reload.last_result
    assert other.reload.active_run_id
  end

end
