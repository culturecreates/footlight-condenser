require "test_helper"

class Distillator::TransitionRunTest < ActiveSupport::TestCase
  setup do
    @website = Website.create!(name: "Run tests", seedurl: "run-tests", graph_name: "https://example.org/runs", default_language: "en", distillator_mode: "shadow")
  end

  test "requests deduplicate active runs" do
    first = Distillator::TransitionRun.request!(website: @website)
    second = Distillator::TransitionRun.request!(website: @website)
    assert first.created?
    assert_not second.created?
    assert_equal first.run.id, second.run.id
    assert_equal 1, @website.transition_runs.count
  end

  test "first recorded phase does not end pending state or publish partial evidence" do
    run = Distillator::TransitionRun.request!(website: @website).run
    assert_raises(RuntimeError) do
      run.execute do
        record(run, "fetch_parity")
        assert @website.reload.pending_transition_batch_check?
        assert_empty @website.latest_transition_evidences_by_kind
        raise "interrupted after fetch"
      end
    end
    assert_equal "failed", run.reload.status
    assert_not @website.pending_transition_batch_check?
    assert_empty @website.latest_transition_evidences_by_kind
    assert_match "failed", @website.transition_run_blocker
  end

  test "complete results publish together and duplicate job delivery does not execute twice" do
    run = Distillator::TransitionRun.request!(website: @website).run
    run.execute { record_all(run) }
    assert_equal "completed", run.reload.status
    assert_equal 3, @website.latest_transition_evidences_by_kind.length
    assert_nil @website.transition_run_blocker
    run.execute { flunk "Completed runs must not execute again" }
  end

  test "failed new attempt preserves previous complete report without mixing phases" do
    first = Distillator::TransitionRun.request!(website: @website).run
    first.execute { record_all(first) }
    second = Distillator::TransitionRun.request!(website: @website).run
    assert_raises(RuntimeError) { second.execute { record(second, "fetch_parity", status: :failed); raise "interrupted" } }
    assert_equal [first.id], @website.latest_transition_evidences_by_kind.values.map(&:transition_run_id).uniq
    assert_match "failed", @website.transition_run_blocker
  end

  test "changed source configuration prevents publishing an in-flight result" do
    run = Distillator::TransitionRun.request!(website: @website).run
    assert_raises(Distillator::TransitionRun::ConfigurationChanged) do
      run.execute do
        record_all(run)
        Source.create!(website: @website, property: properties(:four), algorithm_value: "manual=Changed", language: "en", selected: true)
      end
    end
    assert_equal "failed", run.reload.status
    assert_empty @website.latest_transition_evidences_by_kind
  end

  test "a configuration edit after completion invalidates promotion evidence" do
    run = Distillator::TransitionRun.request!(website: @website).run
    run.execute { record_all(run) }
    @website.update!(default_language: "fr")
    assert_match "configuration changed", @website.transition_run_blocker
  end

  test "datatype configuration edits invalidate completed extraction evidence" do
    definition = Property.create!(label: "Run datatype", value_datatype: "MyString", uri: "https://example.org/run-type", rdfs_class: rdfs_classes(:one))
    @website.sources.create!(property: definition, algorithm_value: "manual=Value", language: "en", selected: true)
    run = Distillator::TransitionRun.request!(website: @website).run
    run.execute { record_all(run) }
    # Same-second edits must invalidate even when updated_at cannot distinguish them.
    definition.update_columns(value_datatype: "xsd:date")
    assert_match "configuration changed", @website.transition_run_blocker
  end

  test "same-second source edits invalidate the fingerprint without relying on updated_at" do
    source = @website.sources.create!(property: properties(:four), algorithm_value: "manual=Before", language: "en", selected: true)
    run = Distillator::TransitionRun.request!(website: @website).run
    run.execute { record_all(run) }
    source.update_columns(algorithm_value: "manual=After")
    assert_match "configuration changed", @website.transition_run_blocker
  end

  test "incomplete phase coverage cannot complete a run" do
    run = Distillator::TransitionRun.request!(website: @website).run
    assert_raises(Distillator::TransitionRun::ConfigurationChanged) { run.execute { record(run, "fetch_parity") } }
    assert_equal "failed", run.reload.status
  end

  test "expired run releases the active slot and cannot publish later" do
    old = nil
    travel_to 2.hours.ago do
      old = Distillator::TransitionRun.request!(website: @website).run
    end
    current = Distillator::TransitionRun.request!(website: @website)
    assert current.created?
    assert_equal "failed", old.reload.status
    assert_not_equal old.id, current.run.id
    old.execute { flunk "Expired run must not execute" }
  end

  test "evidence recording appends immutable attempts" do
    run = Distillator::TransitionRun.request!(website: @website).run
    first = second = nil
    run.execute do
      first = record(run, "fetch_parity", status: :pending)
      second = record(run, "fetch_parity", status: :checked)
      record(run, "statement_delta")
      record(run, "export_diff")
    end
    assert_not_equal first.id, second.id
    assert_equal "pending", first.reload.status
    assert_raises(RuntimeError) { record(run, "fetch_parity") }
  end

  private

  def record_all(run)
    Distillator::TransitionEvidence::REPORT_CHECK_KINDS.each { |kind| record(run, kind) }
  end

  def record(run, kind, status: :checked)
    Distillator::TransitionEvidenceRecorder.call(website: @website, transition_run: run, url: "https://example.org/event",
      check_kind: kind, status: status, statement_count_delta_acceptable: true, export_diff_checked: true)
  end
end
