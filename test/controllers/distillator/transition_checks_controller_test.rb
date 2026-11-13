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
    assert_redirected_to distillator_transition_check_path(target.latest_transition_run)
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
    assert_redirected_to distillator_transition_check_path(target.latest_transition_run)
  end

  test "enqueue failure marks the run failed and permits retry" do
    target = websites(:one)
    Distillator::TransitionCheckJob.stubs(:perform_later).returns(false)
    post distillator_transition_checks_path, params: { website_id: target.id }
    assert_equal "failed", target.latest_transition_run.status
    assert_includes flash[:alert], "Unable to queue"
    assert_nil flash[:notice]
    assert_redirected_to distillator_transition_check_path(target.latest_transition_run)
    assert Distillator::TransitionRun.request!(website: target).created?
  end

  test "successful submission follows its run instead of returning to a static website section" do
    target = Website.create!(
      name: "Transition target",
      seedurl: "transition-target-return",
      graph_name: "https://example.org/transition-target-return",
      default_language: "en",
      distillator_mode: "shadow"
    )

    Distillator::TransitionCheckRunner.expects(:call).never

    post distillator_transition_checks_path, params: { website_id: target.id, return_to: website_path(target, anchor: "website-transition") }

    assert_redirected_to distillator_transition_check_path(target.latest_transition_run)
    assert_equal "Transition check ##{target.latest_transition_run.id} queued.", flash[:notice]
  end

  test "successful submission follows its run even with a deliberate relative return path" do
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

    assert_redirected_to distillator_transition_check_path(target.latest_transition_run)
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

    assert_redirected_to distillator_transition_check_path(target.latest_transition_run)
  end

  test "custom quantity and strictness queue a scoped run without changing the website" do
    target = websites(:two)
    mode = target.distillator_mode
    post distillator_transition_checks_path, params: { website_id: target.id,
      check_options: { sample_mode: "count", sample_size: "50", strictness: "strict" } }
    assert_redirected_to distillator_transition_check_path(target.latest_transition_run)
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
    assert_redirected_to distillator_transition_check_path(target.latest_transition_run)
  end

  test "status follows queued running and completed without changing Legacy mode or publishing partial results" do
    target = websites(:two)
    target.update!(distillator_mode: "legacy")
    run = Distillator::TransitionRun.request!(website: target, options: { sample_mode: "count", sample_size: 10, strictness: "strict" }).run
    expected_report = distillator_shadow_report_site_path(target, run_id: run.id, anchor: "transition-report-summary")
    Distillator::TransitionCheckRunner.expects(:call).never
    Distillator::FetchService.expects(:fetch).never

    2.times do
      assert_no_difference ["Distillator::TransitionRun.count", "Statement.count", "Distillator::RolloutEvent.count"] do
        get distillator_transition_check_path(run)
      end
      assert_response :success
      assert_select '[data-transition-run][data-run-id="' + run.id.to_s + '"][data-status="queued"]'
      assert_select '[data-run-failed][hidden]'
      assert_select '[data-transition-context]', count: 0
      assert_select '[data-operator-context-card]', count: 0
      assert_includes response.body, "Up to 10 publishable event pages"
      assert_includes response.body, "Strict: differences in any selected field block activation"
    end
    get distillator_transition_check_path(run, format: :json)
    assert_equal "queued", response.parsed_body["status"]
    assert_equal expected_report, response.parsed_body["report_url"]
    assert_equal "no-store", response.headers["Cache-Control"]

    run.execute do
      run.transition_evidences.create!(website: target, url: "https://example.org/event", check_kind: "fetch_parity", status: "failed", checked_at: Time.current)
      get distillator_transition_check_path(run, format: :json)
      assert_equal "running", response.parsed_body["status"]
      assert_equal ["Fetch"], response.parsed_body["phases_recorded"]
      %w[statement_delta export_diff].each do |kind|
        run.transition_evidences.create!(website: target, url: "https://example.org/event", check_kind: kind, status: "pending", checked_at: Time.current)
      end
    end
    get distillator_transition_check_path(run, format: :json)
    assert_equal "completed", response.parsed_body["status"]
    assert_includes response.parsed_body["message"], "completion does not mean parity passed"
    assert_equal ["Fetch", "Statements", "Export"], response.parsed_body["phases_recorded"]
    assert_equal expected_report, response.parsed_body["report_url"]
    assert_equal "legacy", target.reload.distillator_mode
    assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs
  end

  test "failure stays visible and retry preserves scope with a new run" do
    target = websites(:two)
    run = Distillator::TransitionRun.request!(website: target, options: { sample_mode: "all", strictness: "strict" }).run
    run.fail!("Worker could not finish the comparison")
    get distillator_transition_check_path(run)
    assert_response :success
    assert_select '[data-run-failed]:not([hidden]) form[action="' + distillator_transition_checks_path + '"]' do
      assert_select 'input[name="check_options[sample_mode]"][value="all"]'
      assert_select 'input[name="check_options[strictness]"][value="strict"]'
    end
    get distillator_transition_check_path(run, format: :json)
    assert_equal "failed", response.parsed_body["status"]
    assert_equal "Worker could not finish the comparison", response.parsed_body["message"]

    post distillator_transition_checks_path, params: { website_id: target.id, check_options: run.options.to_h }
    replacement = target.latest_transition_run
    assert_not_equal run.id, replacement.id
    assert_equal run.options.to_h, replacement.options.to_h
    assert_equal "failed", run.reload.status
    assert_redirected_to distillator_transition_check_path(replacement)
    assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.length
  end

  test "an expired worker lease stops polling and permits a new run without mutating on GET" do
    target = websites(:two)
    run = Distillator::TransitionRun.request!(website: target).run
    run.update!(status: "running", requested_at: 2.hours.ago, started_at: 2.hours.ago)
    get distillator_transition_check_path(run, format: :json)
    assert_equal "expired", response.parsed_body["status"]
    assert_includes response.parsed_body["message"], "Retry"
    assert_equal "running", run.reload.status
    post distillator_transition_checks_path, params: { website_id: target.id }
    assert_not_equal run.id, target.latest_transition_run.id
    assert_equal "failed", run.reload.status
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
