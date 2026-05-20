require "test_helper"

class Distillator::FetchModeTest < ActiveSupport::TestCase
  setup do
    @old_mode = ENV["DISTILLATOR_FETCH_MODE"]
  end

  teardown do
    ENV["DISTILLATOR_FETCH_MODE"] = @old_mode
  end

  test "current remains an env helper defaulting to active" do
    ENV["DISTILLATOR_FETCH_MODE"] = nil

    assert_equal :active, Distillator::FetchMode.current
    assert Distillator::FetchMode.active?
  end

  test "current resolves internal input alias to active" do
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"

    assert_equal :active, Distillator::FetchMode.current
    assert Distillator::FetchMode.active?
  end

  test "current resolves shadow mode from env for legacy helper callers" do
    ENV["DISTILLATOR_FETCH_MODE"] = "shadow"

    assert_equal :shadow, Distillator::FetchMode.current
    assert Distillator::FetchMode.shadow?
  end

  test "unknown mode falls back to active" do
    ENV["DISTILLATOR_FETCH_MODE"] = "surprise"

    assert_equal :active, Distillator::FetchMode.current
  end

  test "blank mode falls back to active" do
    ENV["DISTILLATOR_FETCH_MODE"] = "   "

    assert_equal :active, Distillator::FetchMode.current
  end

  test "mixed case mode is normalized" do
    ENV["DISTILLATOR_FETCH_MODE"] = " ShAdOw "

    assert_equal :shadow, Distillator::FetchMode.current
  end

  test "internal input alias resolves to active mode" do
    assert_equal :active, Distillator::FetchMode.parse("internal")
  end

  test "execution modes expose active as the canonical public mode" do
    assert_equal %w[legacy active shadow], Distillator::FetchMode::EXECUTION_MODES
    assert_equal({ "internal" => "active" }, Distillator::FetchMode::ALIASES)
  end

  test "active website resolves to active mode" do
    website = websites(:one)
    website.update!(distillator_mode: "active")

    assert_equal :active, Distillator::FetchMode.rollout_mode(website: website)
    assert_equal :active, Distillator::FetchMode.resolve(website: website)
  end

  test "rollout resolution object uses safe legacy default without website context" do
    ENV["DISTILLATOR_FETCH_MODE"] = nil

    resolution = Distillator::FetchMode.rollout_resolution_object

    assert_equal :legacy, resolution.execution_mode
    assert_equal :legacy, resolution.rollout_mode
    assert_equal :wringer, resolution.active_backend
    assert_equal :default, resolution.source
    assert_nil resolution.requested_mode
  end

  test "resolve uses safe legacy default when no website context is present" do
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"

    resolution = Distillator::FetchMode.resolution

    assert_equal :legacy, resolution.mode
    assert_equal :default, resolution.source
    assert_equal :legacy, Distillator::FetchMode.resolve
    assert_equal :legacy, Distillator::FetchMode.rollout_mode
  end

  test "rollout resolution ignores env internal without website context" do
    ENV["DISTILLATOR_FETCH_MODE"] = "internal"

    resolution = Distillator::FetchMode.rollout_resolution_object

    assert_equal :legacy, resolution.execution_mode
    assert_equal :legacy, resolution.rollout_mode
    assert_equal :wringer, resolution.active_backend
    assert_equal :default, resolution.source
  end

  test "website rollout wins over legacy env default" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    website = websites(:one)
    website.update!(distillator_mode: "active")

    resolution = Distillator::FetchMode.resolution(website: website)

    assert_equal :active, resolution.mode
    assert_equal :website, resolution.source
  end

  test "rollout resolution object maps active website to condenser backend" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"
    website = websites(:one)
    website.update!(distillator_mode: "active")

    resolution = Distillator::FetchMode.rollout_resolution_object(website: website)

    assert_equal :active, resolution.execution_mode
    assert_equal :active, resolution.rollout_mode
    assert_equal :internal, resolution.dispatch_mode
    assert_equal :condenser, resolution.active_backend
    assert_equal :website, resolution.source
    assert_equal website.id, resolution.website_id
  end

  test "resolve reports env source only for safe legacy env without website context" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"

    resolution = Distillator::FetchMode.resolution

    assert_equal :legacy, resolution.mode
    assert_equal :env, resolution.source
  end

  test "explicit internal alias remains available for diagnostic compatibility" do
    ENV["DISTILLATOR_FETCH_MODE"] = "legacy"

    resolution = Distillator::FetchMode.resolution(explicit_mode: :internal)
    rollout = Distillator::FetchMode.rollout_resolution(explicit_mode: :internal)
    rollout_object = Distillator::FetchMode.rollout_resolution_object(explicit_mode: :internal)

    assert_equal :active, resolution.mode
    assert_equal :explicit, resolution.source
    assert_equal :active, rollout.mode
    assert_equal :explicit, rollout.source
    assert_equal :active, rollout_object.execution_mode
    assert_equal :active, rollout_object.rollout_mode
    assert_equal :internal, rollout_object.dispatch_mode
    assert_equal :condenser, rollout_object.active_backend
    assert_equal :explicit, rollout_object.source
    assert_equal :internal, rollout_object.requested_mode
  end

  test "parse fails safe for nil blank and invalid values" do
    assert_equal :active, Distillator::FetchMode.parse(nil)
    assert_equal :active, Distillator::FetchMode.parse("")
    assert_equal :active, Distillator::FetchMode.parse("not-a-mode")
    assert_equal :active, Distillator::FetchMode.parse("INTERNAL")
  end

  test "fetch mode resolves active website from website_id only" do
    website = Website.create!(
      name: "fetch-mode-website-id",
      seedurl: "fetch-mode-website-id",
      graph_name: "https://example.org/fetch-mode-website-id",
      default_language: "en",
      distillator_mode: "active"
    )

    mode = Distillator::FetchMode.resolve(
      website: nil,
      website_id: website.id,
      log_context: {}
    )

    assert_equal :active, mode
    assert_equal :website_id, Distillator::FetchMode.resolution(website_id: website.id).source
  end

  test "fetch mode resolves active website from log_context website_id only" do
    website = Website.create!(
      name: "fetch-mode-log-context",
      seedurl: "fetch-mode-log-context",
      graph_name: "https://example.org/fetch-mode-log-context",
      default_language: "en",
      distillator_mode: "active"
    )

    mode = Distillator::FetchMode.resolve(
      website: nil,
      website_id: nil,
      log_context: { website_id: website.id }
    )

    assert_equal :active, mode
    assert_equal :website_id, Distillator::FetchMode.resolution(log_context: { website_id: website.id }).source
  end
end
