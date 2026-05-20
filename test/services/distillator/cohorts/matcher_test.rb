require "test_helper"

class Distillator::Cohorts::MatcherTest < ActiveSupport::TestCase
  test "matches a website by seedurl" do
    website = build_website(seedurl: "hector-charland-com", name: "Hector Charland")

    assert_equal true, Distillator::Cohorts::Matcher.match?(website, "lavitrine_pipeline")
  end

  test "matches hyphenated cohort names against normalized website names" do
    website = build_website(seedurl: "other-seed", name: "Tout Culture")

    assert_equal true, Distillator::Cohorts::Matcher.match?(website, "lavitrine_pipeline")
  end

  test "matches derived names and domain like code values" do
    website = build_website(
      seedurl: "other-seed",
      name: "Other name",
      graph_name: "https://derived-grandtheatre.qc.ca/"
    )

    assert_equal true, Distillator::Cohorts::Matcher.match?(website, "lavitrine_pipeline")
  end

  test "normalizes protocols domains and trailing slashes" do
    assert_equal "placedesarts-com", Distillator::Cohorts::Matcher.normalize("https://www.placedesarts.com/")
    assert_equal "culture-mauricie", Distillator::Cohorts::Matcher.normalize("Culture Mauricie")
  end

  test "returns false for non cohort websites" do
    website = build_website(seedurl: "outside-feed", name: "Outside Feed")

    assert_equal false, Distillator::Cohorts::Matcher.match?(website, "lavitrine_pipeline")
  end

  private

  def build_website(seedurl:, name:, graph_name: "https://example.org/feed")
    Website.new(
      name: name,
      seedurl: seedurl,
      graph_name: graph_name,
      default_language: "en",
      distillator_mode: "legacy"
    )
  end
end
