require "test_helper"

class Distillator::RolloutCopyTest < ActiveSupport::TestCase
  test "provides centralized canonical rollout labels descriptions and cache action labels" do
    assert_equal "Legacy", Distillator::RolloutCopy.label(:legacy)
    assert_equal "Shadow", Distillator::RolloutCopy.label(:shadow)
    assert_equal "Active", Distillator::RolloutCopy.label(:active)
    assert_equal "Production mode", Distillator::RolloutCopy.rollout_panel_title

    assert_equal "Wringer serves production.", Distillator::RolloutCopy.description(:legacy)
    assert_equal "Wringer serves production while Condenser is checked in the background.", Distillator::RolloutCopy.description(:shadow)
    assert_equal "Condenser serves production while Wringer stays available for diagnostics.", Distillator::RolloutCopy.description(:active)

    assert_equal "Open active cache", Distillator::RolloutCopy.active_cache_label
    assert_equal "Open Condenser cache", Distillator::RolloutCopy.condenser_cache_label
    assert_equal "Inspect legacy Wringer", Distillator::RolloutCopy.legacy_inspection_label
    assert_equal "Compare Condenser vs Wringer", Distillator::RolloutCopy.compare_label
  end

  test "separates production state copy from diagnostic state copy" do
    assert_equal %i[legacy shadow active], Distillator::RolloutCopy.production_states.keys
    assert_equal %i[replay unknown], Distillator::RolloutCopy.diagnostic_states.keys
  end

  test "normalizes active and internal to the same operator-facing rollout state" do
    assert_equal :active, Distillator::RolloutCopy.normalize(:active)
    assert_equal :active, Distillator::RolloutCopy.normalize(:internal)
    assert_equal :unknown, Distillator::RolloutCopy.normalize(:bogus)
  end

  test "provides canonical website form option copy" do
    assert_equal [
      ["Legacy", "legacy"],
      ["Shadow", "shadow"],
      ["Active", "active"]
    ], Distillator::RolloutCopy.website_form_options
  end

  test "website index filter options exclude replay" do
    values = Distillator::RolloutCopy.website_index_filter_options.map(&:last)

    refute_includes values, "replay"
    assert_includes values, "legacy"
    assert_includes values, "shadow"
    assert_includes values, "active"
  end

  test "operator rollout copy avoids internal and phased rollout wording" do
    operator_copy = [
      Distillator::RolloutCopy.rollout_panel_title,
      Distillator::RolloutCopy.label(:legacy),
      Distillator::RolloutCopy.label(:shadow),
      Distillator::RolloutCopy.label(:active),
      Distillator::RolloutCopy.description(:legacy),
      Distillator::RolloutCopy.description(:shadow),
      Distillator::RolloutCopy.description(:active),
      Distillator::RolloutCopy.next_step(:legacy),
      Distillator::RolloutCopy.next_step(:shadow),
      Distillator::RolloutCopy.next_step(:active)
    ].join(" ").downcase

    refute_includes operator_copy, "internal"
    refute_includes operator_copy, "replay"
    refute_includes operator_copy, "new cache"
    refute_includes operator_copy, "phase"
    refute_includes operator_copy, "preview"
    refute_includes operator_copy, "distillator rollout"
  end
end
