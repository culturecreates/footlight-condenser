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
    assert_equal [target.id], job[:args]
    assert_redirected_to distillator_shadow_report_site_path(target)
    assert_equal "shadow", target.reload.distillator_mode
    assert_equal "legacy", other.reload.distillator_mode
    assert_equal 0, target.transition_evidences.count
    assert_equal 0, other.transition_evidences.count
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
    assert_equal "Transition batch check queued. The latest transition report will update as evidence is recorded.", flash[:notice]
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
end
