require "test_helper"

class Distillator::ProductionPreflightTest < ActiveSupport::TestCase
  setup do
    @old_runtime = ENV["DISTILLATOR_RUNTIME"]
    @old_rails_env = ENV["RAILS_ENV"]
    ApplicationController.helpers.stubs(:get_wringer_url_per_environment).returns("http://wringer.example")
    Website.update_all(distillator_mode: "shadow")
  end

  teardown do
    ENV["DISTILLATOR_RUNTIME"] = @old_runtime
    ENV["RAILS_ENV"] = @old_rails_env
  end

  test "staging preflight fails when legacy websites remain" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    Website.create!(
      name: "Legacy staging website",
      seedurl: "legacy-staging-website",
      graph_name: "https://legacy-staging-website.example/graph",
      default_language: "en",
      distillator_mode: "legacy"
    )

    result = Distillator::ProductionPreflight.call
    entry = result.entries.find { |item| item.label == "Staging rollout modes" }

    assert_not_nil entry
    assert_equal false, entry.ok
    assert_includes entry.value, "Staging requires every website to be Shadow or Active."
    assert_includes entry.value, "1 invalid websites"
  end

  test "staging preflight passes when every website is shadow or active" do
    ENV["DISTILLATOR_RUNTIME"] = "staging"
    Website.create!(
      name: "Shadow staging website",
      seedurl: "shadow-staging-website",
      graph_name: "https://shadow-staging-website.example/graph",
      default_language: "en",
      distillator_mode: "shadow"
    )
    Website.create!(
      name: "Active staging website",
      seedurl: "active-staging-website",
      graph_name: "https://active-staging-website.example/graph",
      default_language: "en",
      distillator_mode: "active"
    )

    result = Distillator::ProductionPreflight.call
    entry = result.entries.find { |item| item.label == "Staging rollout modes" }

    assert_not_nil entry
    assert_equal true, entry.ok
    assert_includes entry.value, "Staging requires every website to be Shadow or Active."
    assert_includes entry.value, "OK"
  end

  test "production preflight does not add staging rollout entry" do
    ENV["DISTILLATOR_RUNTIME"] = "production"

    result = Distillator::ProductionPreflight.call

    assert_nil result.entries.find { |item| item.label == "Staging rollout modes" }
  end
end
