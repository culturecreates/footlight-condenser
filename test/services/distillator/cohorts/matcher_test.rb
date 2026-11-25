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

  test "client sites cohort matches the eleven named websites" do
    names = [
      "Co-motion Laval", "Culture 3R", "Culture La Tuque",
      "Culture Mauricie - lepointdevente - Trois-Rivieres", "Gatineau (Ville)",
      "Maison de culture Gatineau (Salle Odyssée)", "Minotaure",
      "Tourisme des Chenaux", "Tourisme Maskinongé", "Tourisme Shawinigan",
      "Tourisme Trois-Rivieres"
    ]
    names.each do |name|
      website = build_website(seedurl: "unrelated-seed", name: name)
      assert Distillator::Cohorts::Matcher.match?(website, "client_sites"), "Missing client: #{name}"
    end
  end

  test "client membership uses exact normalized values, not partial matches" do
    website = build_website(seedurl: "unrelated-seed", name: "Culture Mauricie - ResourceList")
    refute Distillator::Cohorts::Matcher.match?(website, "client_sites")
    assert Distillator::Cohorts::Matcher.match?(build_website(seedurl: "co-motion-ca", name: "Renamed presenter"), "client_sites")
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
