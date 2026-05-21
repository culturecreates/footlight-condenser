require "test_helper"

class DistillatorTransitionCopyTest < ActiveSupport::TestCase
  LIVE_TRANSITION_FILES = [
    Rails.root.join("app/views/shared/_transition_context.html.erb"),
    Rails.root.join("app/views/websites/show.html.erb"),
    Rails.root.join("app/views/websites/index.html.erb"),
    Rails.root.join("app/views/distillator/shadow_reports/index.html.erb"),
    Rails.root.join("app/views/distillator/shadow_reports/show.html.erb"),
    Rails.root.join("docs/distillator_migration.md")
  ].freeze

  FORBIDDEN_PHRASES = [
    "Phase I",
    "preview only",
    "first UI batch",
    "All shadow sites",
    "shadow websites matched",
    "Apify is required",
    "internal rollout step",
    "replay rollout step"
  ].freeze

  test "live transition workflow files do not reintroduce retired rollout wording" do
    contents = LIVE_TRANSITION_FILES.to_h { |path| [path, File.read(path)] }

    FORBIDDEN_PHRASES.each do |phrase|
      contents.each do |path, content|
        refute_includes content, phrase, "#{path} unexpectedly included #{phrase.inspect}"
      end
    end
  end
end

class DistillatorTransitionContextIntegrationTest < ActionDispatch::IntegrationTest
  test "webpages index renders compact transition context from website cookie" do
    website = Website.create!(
      name: "Context website",
      seedurl: "context-website",
      graph_name: "https://example.org/context-website",
      default_language: "en",
      distillator_mode: "shadow"
    )

    get website_url(website)
    assert_response :success

    get webpages_url

    assert_response :success
    assert_includes @response.body, "Transition context"
    assert_includes @response.body, website.name
    assert_includes @response.body, "Current mode:</strong> Shadow comparison"
    assert_includes @response.body, "Production backend:</strong> Wringer"
    assert_includes @response.body, "Transition report"
  end

  test "webpages index stays compact when no website context exists" do
    get webpages_url

    assert_response :success
    assert_not_includes @response.body, "Transition context"
  end
end
