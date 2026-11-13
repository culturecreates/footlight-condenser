require "test_helper"

class Distillator::TransitionEvidenceRecorderTest < ActiveSupport::TestCase
  test "records evidence per website and url" do
    website = Website.create!(
      name: "Recorder site",
      seedurl: "hector-charland-com",
      graph_name: "https://example.org/recorder-site",
      default_language: "en",
      distillator_mode: "shadow"
    )

    evidence = Distillator::TransitionEvidenceRecorder.call(
      website: website,
      url: "hector-charland-com/events/1",
      check_kind: :export_diff,
      status: :checked,
      export_diff_checked: true,
      rdf_added_count: 0,
      rdf_removed_count: 0
    )

    assert_equal website, evidence.website
    assert_equal "export_diff", evidence.check_kind
    assert_equal true, evidence.export_diff_checked
    assert_equal "lavitrine_pipeline", evidence.cohort_key
    assert_match %r{\Ahttp://hector-charland-com/events/1\z}, evidence.url
  end

  test "appends a new evidence record without rewriting previous attempts" do
    website = Website.create!(
      name: "Recorder site",
      seedurl: "outside-feed",
      graph_name: "https://example.org/recorder-site-2",
      default_language: "en",
      distillator_mode: "shadow"
    )

    first = Distillator::TransitionEvidenceRecorder.call(
      website: website,
      url: "outside-feed/events/1",
      check_kind: :statement_delta,
      status: :pending
    )

    assert_difference("Distillator::TransitionEvidence.count", 1) do
      second = Distillator::TransitionEvidenceRecorder.call(
        website: website,
        url: "outside-feed/events/1",
        check_kind: :statement_delta,
        status: :checked,
        statement_delta: 4,
        statement_count_delta_acceptable: true
      )
      assert_not_equal first.id, second.id
      assert_equal "pending", first.reload.status
      assert_equal "checked", second.status
      assert_equal 4, second.statement_delta
    end
  end
end
