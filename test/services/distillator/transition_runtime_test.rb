require "test_helper"

class Distillator::TransitionRuntimeTest < ActiveSupport::TestCase
  setup do
    @old_runtime = ENV["DISTILLATOR_RUNTIME"]
    @old_rails_env = ENV["RAILS_ENV"]
    @old_override_flag = ENV["DISTILLATOR_ALLOW_ACTIVE_OVERRIDE"]
    @old_heroku_app_name = ENV["HEROKU_APP_NAME"]
    @old_app_name = ENV["APP_NAME"]
    @old_heroku_parent_app_name = ENV["HEROKU_PARENT_APP_NAME"]
  end

  teardown do
    ENV["DISTILLATOR_RUNTIME"] = @old_runtime
    ENV["RAILS_ENV"] = @old_rails_env
    ENV["DISTILLATOR_ALLOW_ACTIVE_OVERRIDE"] = @old_override_flag
    ENV["HEROKU_APP_NAME"] = @old_heroku_app_name
    ENV["APP_NAME"] = @old_app_name
    ENV["HEROKU_PARENT_APP_NAME"] = @old_heroku_parent_app_name
  end

  test "staging is true for explicit runtime" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    ENV["RAILS_ENV"] = "production"
    ENV["HEROKU_APP_NAME"] = nil

    assert_equal true, Distillator::TransitionRuntime.staging?
  end

  test "staging is true for known staging app" do
    ENV["DISTILLATOR_RUNTIME"] = nil
    ENV["RAILS_ENV"] = "production"
    ENV["HEROKU_APP_NAME"] = "footlight-condenser-test-c24c162bb7c8"

    assert_equal true, Distillator::TransitionRuntime.staging?
  end

  test "staging stays false for random app names containing test" do
    ENV["DISTILLATOR_RUNTIME"] = nil
    ENV["RAILS_ENV"] = "production"
    ENV["HEROKU_APP_NAME"] = nil
    ENV["APP_NAME"] = "random-test-app"

    assert_equal false, Distillator::TransitionRuntime.staging?
  end

  test "allow active override remains true on staging" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))

    assert_equal true, Distillator::TransitionRuntime.allow_active_override?
  ensure
    Rails.unstub(:env)
  end

  test "staging invalid rollout mode scope includes legacy blank and internal values" do
    shadow = create_website_with_mode("shadow-scope", "shadow")
    active = create_website_with_mode("active-scope", "active")
    legacy = create_website_with_mode("legacy-scope", "legacy")
    blank = create_website_with_mode("blank-scope", "legacy")
    blank.update_column(:distillator_mode, "")
    internal = create_website_with_mode("internal-scope", "legacy")
    internal.update_column(:distillator_mode, "internal")

    ids = Distillator::TransitionRuntime.staging_invalid_rollout_mode_scope.order(:id).pluck(:id)

    assert_includes ids, legacy.id
    assert_includes ids, blank.id
    assert_includes ids, internal.id
    assert_not_includes ids, shadow.id
    assert_not_includes ids, active.id
  end

  test "staging invalid rollout mode scope excludes shadow and active from repair set" do
    shadow = create_website_with_mode("shadow-repair-scope", "shadow")
    active = create_website_with_mode("active-repair-scope", "active")

    ids = Distillator::TransitionRuntime.staging_invalid_rollout_mode_scope.order(:id).pluck(:id)

    assert_not_includes ids, shadow.id
    assert_not_includes ids, active.id
  end

  private

  def create_website_with_mode(seedurl, mode)
    Website.create!(
      name: "Runtime #{seedurl}",
      seedurl: seedurl,
      graph_name: "https://#{seedurl}.example/graph",
      default_language: "en",
      distillator_mode: mode
    )
  end
end
