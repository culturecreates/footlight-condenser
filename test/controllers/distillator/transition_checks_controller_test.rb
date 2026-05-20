require "test_helper"

class Distillator::TransitionChecksControllerTest < ActionDispatch::IntegrationTest
  test "transition check runs for one website only and does not change rollout mode" do
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

    Distillator::TransitionCheckRunner.expects(:call).with(website: target).once.returns(
      Distillator::TransitionCheckRunner::Result.new(website: target, records: {})
    )

    post distillator_transition_checks_path, params: { website_id: target.id }

    assert_redirected_to website_url(target)
    assert_equal "shadow", target.reload.distillator_mode
    assert_equal "legacy", other.reload.distillator_mode
    assert_equal 0, target.transition_evidences.count
    assert_equal 0, other.transition_evidences.count
  end
end
