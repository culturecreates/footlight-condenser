require "test_helper"
require "minitest/mock"

class Distillator::TransitionCheckJobTest < ActiveJob::TestCase
  test "perform calls transition check runner for the website id" do
    website = Website.create!(
      name: "Transition job website",
      seedurl: "transition-job-website",
      graph_name: "https://example.org/transition-job-website",
      default_language: "en",
      distillator_mode: "shadow"
    )

    request = Distillator::TransitionRun.request!(website: website)
    calls = []
    runner = ->(website:, transition_run:) do
      calls << transition_run.id
      Distillator::TransitionEvidence::REPORT_CHECK_KINDS.each do |kind|
        transition_run.transition_evidences.create!(website: website, url: "https://example.org/job", check_kind: kind,
          status: "pending", checked_at: Time.current)
      end
    end
    Distillator::TransitionCheckRunner.stub(:call, runner) do
      Distillator::TransitionCheckJob.perform_now(website.id, run_id: request.run.id)
      assert_equal "completed", request.run.reload.status
      # At-least-once job delivery must not execute the same run twice.
      Distillator::TransitionCheckJob.perform_now(website.id, run_id: request.run.id)
    end
    assert_equal [request.run.id], calls
  end
end
