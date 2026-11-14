require "test_helper"
require "minitest/mock"

class Distillator::TransitionBatchReconcileJobTest < ActiveJob::TestCase
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @website = event_site("reconcile-pilot")
    @other = event_site("reconcile-other")
    @batch = Distillator::TransitionBatch.request!(website_ids: [@website.id, @other.id], request_key: SecureRandom.uuid)
    @first, @second = @batch.site_transitions.order(:position).to_a
    clear_enqueued_jobs
  end
  teardown { ActiveJob::Base.queue_adapter = @old_adapter }

  test "sweep resumes a group after a committed result lost its continuation" do
    @first.update!(status: "attention", phase: "finished", completed_at: Time.current)
    assert_enqueued_with(job: Distillator::SiteTransitionJob, args: [@second.id, { phase: "queued" }]) { sweep }
    assert_no_enqueued_jobs { sweep }
    travel 61.seconds do
      assert_enqueued_with(job: Distillator::SiteTransitionJob, args: [@second.id, { phase: "queued" }]) { sweep }
    end
    assert_equal "queued", @second.reload.status
    assert_equal "legacy", @other.reload.distillator_mode
  end

  test "sweep also repairs a group committed before its first enqueue" do
    assert_enqueued_with(job: Distillator::SiteTransitionJob, args: [@first.id, { phase: "queued" }]) { sweep }
  end

  test "sweep resumes an unclaimed Active verification handoff without claiming success" do
    @first.update!(status: "running", phase: "postcheck", deadline_at: 1.hour.from_now)
    assert_enqueued_with(job: Distillator::SiteTransitionJob, args: [@first.id, { phase: "postcheck" }]) { sweep }
    assert_nil @first.reload.post_run
    assert_equal "running", @first.status
    assert_equal "queued", @second.reload.status
  end

  test "healthy running phases are left alone" do
    @first.update!(status: "running", phase: "precheck", phase_started_at: Time.current, deadline_at: 1.hour.from_now)
    assert_no_enqueued_jobs { sweep }
  end

  test "expired work gets its recovery guard even when the batch was stopped" do
    @first.update!(status: "running", phase: "postcheck", phase_started_at: 2.hours.ago, deadline_at: 1.minute.ago)
    @batch.stop_remaining!
    assert_enqueued_with(job: Distillator::SiteTransitionWatchdogJob, args: [@first.id]) { sweep }
    assert_equal "cancelled", @second.reload.status
  end

  test "terminal and stopped groups never restart remaining sites" do
    @batch.stop_remaining!
    assert_no_enqueued_jobs { sweep }
  end

  test "an enqueue outage remains retryable and does not prevent another group from resuming" do
    other = event_site("reconcile-third")
    second_batch = Distillator::TransitionBatch.request!(website_ids: [other.id], request_key: SecureRandom.uuid)
    clear_enqueued_jobs
    enqueue = Distillator::SiteTransitionJob.method(:perform_later)
    outage = ->(id, **options) do
      raise "Queue unavailable" if id == @first.id
      enqueue.call(id, **options)
    end
    Distillator::SiteTransitionJob.stub(:perform_later, outage) do
      assert_enqueued_with(job: Distillator::SiteTransitionJob, args: [second_batch.site_transitions.sole.id, { phase: "queued" }]) { sweep }
    end
    assert_nil @batch.reload.last_reconciled_at
    assert_equal "queued", @first.reload.status
    assert_enqueued_with(job: Distillator::SiteTransitionJob, args: [@first.id, { phase: "queued" }]) { sweep }
  end

  private

  def sweep
    Distillator::TransitionBatchReconcileJob.perform_now
  end

  def event_site(seed)
    website = Website.create!(name: seed, seedurl: seed, graph_name: "https://example.org/#{seed}", default_language: "en", distillator_mode: "legacy")
    website.webpages.create!(url: "https://example.org/#{seed}", rdf_uri: "rdf:#{seed}", rdfs_class: rdfs_classes(:one), language: "en")
    website
  end
end
