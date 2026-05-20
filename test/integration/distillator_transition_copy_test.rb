require "test_helper"

class DistillatorTransitionCopyTest < ActiveSupport::TestCase
  LIVE_TRANSITION_FILES = [
    Rails.root.join("app/views/distillator/shadow_reports/index.html.erb"),
    Rails.root.join("app/views/distillator/shadow_reports/show.html.erb"),
    Rails.root.join("docs/distillator_migration.md")
  ].freeze

  FORBIDDEN_PHRASES = [
    "Phase I",
    "preview only",
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
