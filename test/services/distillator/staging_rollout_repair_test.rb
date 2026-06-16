require "test_helper"

class Distillator::StagingRolloutRepairTest < ActiveSupport::TestCase
  setup do
    @old_runtime = ENV["DISTILLATOR_RUNTIME"]
    Website.update_all(distillator_mode: "shadow")
  end

  teardown do
    ENV["DISTILLATOR_RUNTIME"] = @old_runtime
  end

  test "dry run returns invalid website count and list without modifying rows" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    legacy = create_website_with_mode("repair-legacy", "legacy")
    blank = create_website_with_mode("repair-blank", "legacy")
    blank.update_column(:distillator_mode, "")
    active = create_website_with_mode("repair-active", "active")

    result = Distillator::StagingRolloutRepair.call

    assert_equal true, result.success?
    assert_equal true, result.dry_run
    assert_equal 2, result.invalid_count
    assert_equal 0, result.repaired_count
    assert_equal [], result.changed_websites
    assert_equal [legacy.id, blank.id].sort, result.unchanged_websites.map(&:id).sort
    assert_equal [legacy.id, blank.id].sort, result.websites.map(&:id).sort
    assert_equal "legacy", legacy.reload.distillator_mode
    assert_equal "", blank.reload.distillator_mode
    assert_equal "active", active.reload.distillator_mode
  end

  test "apply changes legacy blank internal and replay to shadow and leaves valid rows unchanged" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    legacy = create_website_with_mode("repair-apply-legacy", "legacy")
    blank = create_website_with_mode("repair-apply-blank", "legacy")
    blank.update_column(:distillator_mode, "")
    internal = create_website_with_mode("repair-apply-internal", "legacy")
    internal.update_column(:distillator_mode, "internal")
    replay = create_website_with_mode("repair-apply-replay", "legacy")
    replay.update_column(:distillator_mode, "replay")
    shadow = create_website_with_mode("repair-apply-shadow", "shadow")
    active = create_website_with_mode("repair-apply-active", "active")

    result = Distillator::StagingRolloutRepair.call(apply: true, actor: "test", reason: "Repair invalid staging sites")

    assert_equal true, result.success?
    assert_equal false, result.dry_run
    assert_equal true, result.applied
    assert_equal 4, result.invalid_count
    assert_equal 4, result.repaired_count
    assert_equal [legacy.id, blank.id, internal.id, replay.id].sort, result.changed_websites.map(&:id).sort
    assert_equal [], result.unchanged_websites
    assert_equal "shadow", legacy.reload.distillator_mode
    assert_equal "shadow", blank.reload.distillator_mode
    assert_equal "shadow", internal.reload.distillator_mode
    assert_equal "shadow", replay.reload.distillator_mode
    assert_equal "shadow", shadow.reload.distillator_mode
    assert_equal "active", active.reload.distillator_mode
    assert_equal 1, legacy.rollout_events.where(to_mode: "shadow").count
    assert_equal 1, internal.rollout_events.where(to_mode: "shadow").count
    assert_equal 1, replay.rollout_events.where(to_mode: "shadow").count
  end

  test "apply refuses outside staging and changes nothing" do
    ENV["DISTILLATOR_RUNTIME"] = "production"
    legacy = create_website_with_mode("repair-production-legacy", "legacy")

    result = Distillator::StagingRolloutRepair.call(apply: true)

    assert_equal false, result.success?
    assert_equal false, result.applied
    assert_equal false, result.dry_run
    assert_equal 1, result.invalid_count
    assert_equal 0, result.repaired_count
    assert_includes result.errors, "Staging rollout repair can only run on staging."
    assert_equal [], result.changed_websites
    assert_equal [legacy.id], result.websites.map(&:id)
    assert_equal [legacy.id], result.unchanged_websites.map(&:id)
    assert_equal "legacy", legacy.reload.distillator_mode
    assert_equal 0, legacy.rollout_events.count
  end

  private

  def create_website_with_mode(seedurl, mode)
    Website.create!(
      name: "Repair #{seedurl}",
      seedurl: seedurl,
      graph_name: "https://#{seedurl}.example/graph",
      default_language: "en",
      distillator_mode: mode
    )
  end
end
