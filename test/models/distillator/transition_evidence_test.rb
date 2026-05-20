require "test_helper"

class Distillator::TransitionEvidenceTest < ActiveSupport::TestCase
  test "supports latest evidence lookup by website and kind" do
    website = websites(:one)
    older = Distillator::TransitionEvidence.create!(
      website: website,
      url: "https://example.org/event",
      check_kind: "export_diff",
      status: "checked",
      export_diff_checked: true,
      checked_at: 2.days.ago
    )
    newer = Distillator::TransitionEvidence.create!(
      website: website,
      url: "https://example.org/event",
      check_kind: "export_diff",
      status: "accepted",
      export_diff_accepted: true,
      checked_at: 1.day.ago
    )

    assert_equal newer, Distillator::TransitionEvidence.latest_for_website(website, "export_diff")
    assert_equal newer, Distillator::TransitionEvidence.latest_for_website_ids([website.id])[website.id]["export_diff"]
  end

  test "reports derived satisfaction helpers" do
    evidence = Distillator::TransitionEvidence.new(
      website: websites(:one),
      url: "https://example.org/event",
      check_kind: "statement_delta",
      status: "checked",
      statement_count_delta_acceptable: true,
      checked_at: Time.current
    )

    assert_equal true, evidence.acceptable_statement_delta?
  end
end
