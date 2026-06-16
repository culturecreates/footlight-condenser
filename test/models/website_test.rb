require 'test_helper'

class WebsiteTest < ActiveSupport::TestCase
  test "defaults distillator rollout mode to legacy" do
    website = Website.new(
      name: "Rollout default",
      seedurl: "rollout-default",
      graph_name: "http://example.com/rollout-default",
      default_language: "en"
    )

    website.valid?

    assert_equal "legacy", website.distillator_mode
    assert_equal :legacy, website.distillator_fetch_mode
  end

  test "maps active website rollout to the canonical active fetch mode" do
    website = websites(:one)
    website.distillator_mode = "active"

    assert_equal :active, website.distillator_fetch_mode
  end

  test "website rollout modes stay separate from fetch execution modes" do
    assert_equal %w[legacy shadow active], Website::DISTILLATOR_MODES
    assert_not_includes Website::DISTILLATOR_MODES, "internal"
  end

  test "rejects unsupported distillator rollout modes" do
    website = websites(:one)
    website.distillator_mode = "preview"

    assert_not website.valid?
    assert_includes website.errors[:distillator_mode], "is not included in the list"
  end

  test "rejects replay distillator rollout mode" do
    website = websites(:one)
    website.distillator_mode = "replay"

    assert_not website.valid?
    assert_includes website.errors[:distillator_mode], "is not included in the list"
  end

  test "rejects blank distillator rollout mode" do
    website = websites(:one)
    website.distillator_mode = ""

    assert_not website.valid?
    assert_includes website.errors[:distillator_mode], "is not included in the list"
  end

  test "rejects random distillator rollout mode values" do
    website = websites(:one)
    website.distillator_mode = "banana"

    assert_not website.valid?
    assert_includes website.errors[:distillator_mode], "is not included in the list"
  end

  test "reports la vitrine cohort membership from the matcher" do
    website = Website.new(
      name: "Tout Culture",
      seedurl: "outside-seed",
      graph_name: "http://example.com/tout-culture",
      default_language: "en"
    )

    assert_equal true, website.lavitrine_pipeline?
    assert_equal "lavitrine_pipeline", website.distillator_primary_cohort_key
    assert_equal "La Vitrine pipeline", website.distillator_primary_cohort_label
  end

  test "website exposes latest transition evidence helpers" do
    website = websites(:one)
    evidence = website.transition_evidences.create!(
      url: "https://example.org/export",
      check_kind: "export_diff",
      status: "checked",
      export_diff_checked: true,
      checked_at: Time.current
    )

    assert_equal evidence, website.latest_transition_evidence("export_diff")
    assert_equal evidence, website.latest_transition_evidences_by_kind["export_diff"]
  end

end
