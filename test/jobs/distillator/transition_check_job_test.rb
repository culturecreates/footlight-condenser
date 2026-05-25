require "test_helper"

class Distillator::TransitionCheckJobTest < ActiveJob::TestCase
  test "perform calls transition check runner for the website id" do
    website = Website.create!(
      name: "Transition job website",
      seedurl: "transition-job-website",
      graph_name: "https://example.org/transition-job-website",
      default_language: "en",
      distillator_mode: "shadow"
    )

    Distillator::TransitionCheckRunner.expects(:call).with(website: website.id).once

    Distillator::TransitionCheckJob.perform_now(website.id)
  end
end
