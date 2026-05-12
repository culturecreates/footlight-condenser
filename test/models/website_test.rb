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

  test "maps active website rollout to internal fetch mode" do
    website = websites(:one)
    website.distillator_mode = "active"

    assert_equal :internal, website.distillator_fetch_mode
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
end
