require "test_helper"

class Distillator::TransitionChecksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  teardown do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  test "transition check queues a job for one website only and does not change rollout mode" do
    target = Website.create!(
      name: "Transition target",
      seedurl: "transition-target",
      graph_name: "https://example.org/transition-target",
      default_language: "en",
      distillator_mode: "shadow"
    )
    other = Website.create!(
      name: "Transition other",
      seedurl: "transition-other",
      graph_name: "https://example.org/transition-other",
      default_language: "en",
      distillator_mode: "legacy"
    )

    Distillator::TransitionCheckRunner.expects(:call).never

    assert_difference -> { ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job] == Distillator::TransitionCheckJob } }, 1 do
      post distillator_transition_checks_path, params: { website_id: target.id }
    end

    job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |entry| entry[:job] == Distillator::TransitionCheckJob }
    assert_equal target.id, job[:args].first
    assert_equal target.transition_runs.last.id, job[:args].last["run_id"]
    assert_redirected_to distillator_shadow_report_site_path(target)
    assert_equal "shadow", target.reload.distillator_mode
    assert_equal "legacy", other.reload.distillator_mode
    assert_not_nil target.reload.transition_check_requested_at
    assert_equal 0, target.transition_evidences.count
    assert_equal 0, other.transition_evidences.count
  end

  test "duplicate requests reuse the queued run without another job" do
    target = websites(:one)
    2.times { post distillator_transition_checks_path, params: { website_id: target.id } }
    assert_equal 1, target.transition_runs.active.count
    assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.length
    assert_includes flash[:notice], "already queued"
  end

  test "enqueue failure marks the run failed and permits retry" do
    target = websites(:one)
    Distillator::TransitionCheckJob.stubs(:perform_later).returns(false)
    post distillator_transition_checks_path, params: { website_id: target.id }
    assert_equal "failed", target.latest_transition_run.status
    assert_includes flash[:alert], "Unable to queue"
    assert_nil flash[:notice]
    assert Distillator::TransitionRun.request!(website: target).created?
  end

  test "transition check redirects back to website transition section when return_to is provided" do
    target = Website.create!(
      name: "Transition target",
      seedurl: "transition-target-return",
      graph_name: "https://example.org/transition-target-return",
      default_language: "en",
      distillator_mode: "shadow"
    )

    Distillator::TransitionCheckRunner.expects(:call).never

    post distillator_transition_checks_path, params: { website_id: target.id, return_to: website_path(target, anchor: "website-transition") }

    assert_redirected_to website_path(target, anchor: "website-transition")
    assert_equal "Transition batch check queued. The transition report will update when all phases finish.", flash[:notice]
  end

  test "transition check allows deliberate relative webpages return_to" do
    target = Website.create!(
      name: "Transition target",
      seedurl: "transition-target-webpages",
      graph_name: "https://example.org/transition-target-webpages",
      default_language: "en",
      distillator_mode: "shadow"
    )

    Distillator::TransitionCheckRunner.expects(:call).never

    return_to = "/webpages?seedurl=#{target.seedurl}"
    post distillator_transition_checks_path, params: { website_id: target.id, return_to: return_to }

    assert_redirected_to return_to
  end

  test "transition check rejects unsafe external return_to values" do
    target = Website.create!(
      name: "Transition target",
      seedurl: "transition-target-unsafe",
      graph_name: "https://example.org/transition-target-unsafe",
      default_language: "en",
      distillator_mode: "shadow"
    )

    Distillator::TransitionCheckRunner.expects(:call).never

    post distillator_transition_checks_path, params: { website_id: target.id, return_to: "https://evil.example/steal" }

    assert_redirected_to distillator_shadow_report_site_path(target)
  end

  test "custom quantity and strictness queue a scoped run without changing the website" do
    target = websites(:two)
    mode = target.distillator_mode
    post distillator_transition_checks_path, params: { website_id: target.id,
      check_options: { sample_mode: "count", sample_size: "50", strictness: "strict" } }
    assert_redirected_to distillator_shadow_report_site_path(target)
    assert_equal({ "sample_mode" => "count", "sample_size" => 50, "strictness" => "strict" }, target.latest_transition_run.check_options)
    assert_equal mode, target.reload.distillator_mode
    assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.length
  end

  test "different scope during an active run produces a clear conflict without a second job" do
    target = websites(:two)
    post distillator_transition_checks_path, params: { website_id: target.id }
    post distillator_transition_checks_path, params: { website_id: target.id, check_options: { sample_mode: "all", strictness: "strict" } }
    assert_includes flash[:alert], "different check options"
    assert_nil flash[:notice]
    assert_equal 1, target.transition_runs.count
    assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.length
    assert target.latest_transition_run.options.default?
  end

  test "malformed and invalid options do not create runs or enqueue jobs" do
    target = websites(:two)
    ["all", { sample_mode: "count", sample_size: "-1" }, { strictness: "anything" }, { unexpected: "value" }].each do |options|
      post distillator_transition_checks_path, params: { website_id: target.id, check_options: options }
      assert_redirected_to distillator_shadow_report_site_path(target)
      assert flash[:alert].present?
    end
    assert_equal 0, target.transition_runs.count
    assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs
  end
end
