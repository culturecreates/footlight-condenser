require "test_helper"

class Distillator::RolloutEventRecorderTest < ActiveSupport::TestCase
  test "creates an event when mode changes" do
    website = websites(:one)

    assert_difference("Distillator::RolloutEvent.count", 1) do
      Distillator::RolloutEventRecorder.call(
        website: website,
        from_mode: "shadow",
        to_mode: "active",
        actor: "127.0.0.1",
        readiness_snapshot: { blockers: ["missing_export_diff"], warnings: [] }
      )
    end

    assert_equal "rollout.transition", Distillator::RolloutEvent.order(:created_at).last.readiness_snapshot["event"]
  end

  test "skips no-op mode changes" do
    website = websites(:one)

    assert_no_difference("Distillator::RolloutEvent.count") do
      Distillator::RolloutEventRecorder.call(
        website: website,
        from_mode: "shadow",
        to_mode: "shadow"
      )
    end
  end

  test "marks active to legacy as a rollback event" do
    website = websites(:one)

    Distillator::RolloutEventRecorder.call(
      website: website,
      from_mode: "active",
      to_mode: "legacy"
    )

    assert_equal "rollout.rollback", Distillator::RolloutEvent.order(:created_at).last.readiness_snapshot["event"]
  end
end
