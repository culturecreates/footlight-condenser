require "test_helper"

class Distillator::RolloutCopyTest < ActiveSupport::TestCase
  test "provides centralized canonical rollout labels descriptions and cache action labels" do
    assert_equal "Legacy Wringer active", Distillator::RolloutCopy.label(:legacy)
    assert_equal "Shadow comparison", Distillator::RolloutCopy.label(:shadow)
    assert_equal "Condenser active", Distillator::RolloutCopy.label(:active)

    assert_equal "Wringer remains the production fetch path.", Distillator::RolloutCopy.description(:legacy)
    assert_equal "Wringer serves production results; Condenser compares in the background.", Distillator::RolloutCopy.description(:shadow)
    assert_equal "Condenser serves fetch/cache results; legacy Wringer remains available for inspection.", Distillator::RolloutCopy.description(:active)

    assert_equal "Open active cache", Distillator::RolloutCopy.active_cache_label
    assert_equal "Open Condenser cache", Distillator::RolloutCopy.condenser_cache_label
    assert_equal "Inspect legacy Wringer", Distillator::RolloutCopy.legacy_inspection_label
    assert_equal "Compare Condenser vs Wringer", Distillator::RolloutCopy.compare_label
  end

  test "normalizes active and internal to the same operator-facing rollout state" do
    assert_equal :active, Distillator::RolloutCopy.normalize(:active)
    assert_equal :active, Distillator::RolloutCopy.normalize(:internal)
    assert_equal :unknown, Distillator::RolloutCopy.normalize(:bogus)
  end

  test "provides canonical website form option copy" do
    assert_equal [
      ["Legacy - Wringer active", "legacy"],
      ["Shadow - Wringer production path + Condenser comparison", "shadow"],
      ["Active - Condenser active", "active"]
    ], Distillator::RolloutCopy.website_form_options
  end
end
