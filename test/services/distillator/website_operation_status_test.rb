require "test_helper"

class Distillator::WebsiteOperationStatusTest < ActiveSupport::TestCase
  setup do
    @website = Website.create!(name: "Reviewed site", seedurl: "operation-status",
      default_language: "fr", graph_name: "https://example.org/operations", distillator_mode: "shadow")
    @url = "https://example.org/operations/event"
    @website.webpages.create!(url: @url, language: "fr", rdf_uri: "rdf:operation-event", rdfs_class: rdfs_classes(:one))
    @cache = Distillator::FetchCache.create!(uri_key: CGI.escape(@url), normalized_url: @url,
      html: "<html>ok</html>", body: "<html>ok</html>", scrape_date: 1.hour.ago,
      successful_refresh: 1.hour.ago, headers: {}, signals: { transport_success: true, content_success: true }, final_url: @url)
    @website.transition_evidences.create!(url: @url, check_kind: "fetch_parity", status: "checked", checked_at: 1.hour.ago,
      details: { reason: "review_needed_difference", compare_summary: { review_needed_diffs: ["html_sha256"] } })
    @website.transition_evidences.create!(url: @url, check_kind: "statement_delta", status: "checked", checked_at: 1.hour.ago,
      statement_count_delta_acceptable: true)
    @website.transition_evidences.create!(url: @url, check_kind: "export_diff", status: "checked", checked_at: 1.hour.ago,
      export_diff_checked: true)
    @run = publish_transition_fixture(@website)
    result = Distillator::RolloutTransition.call(website: @website, to_mode: "active", review: true, reason: "Reviewed title and redirect")
    assert result.success?, result.errors.inspect
  end

  test "review acceptance matches the recorded run and survives aging of historical evidence" do
    assert operation.accepted_comparison?
    travel 10.days do
      assert operation.accepted_comparison?
    end
    assert_equal "Activated after review", Distillator::WebsiteOperationStatus.event_label(operation.activation)
    assert_equal "Awaiting active refresh", operation.observed_fetch[:label]
  end

  test "new queued failed or completed checks never inherit the previous manual acceptance" do
    run = @website.transition_runs.create!(status: "queued", requested_at: Time.current,
      configuration_digest: @run.configuration_digest)
    assert_not operation.accepted_comparison?
    run.update!(status: "failed", error_message: "Fetch timed out", completed_at: Time.current)
    assert_not operation.accepted_comparison?
    assert_includes operation.comparison.blockers, "Fetch timed out"
    run.update!(status: "completed", error_message: nil)
    @run.transition_evidences.each do |record|
      run.transition_evidences.create!(record.attributes.except("id", "created_at", "updated_at", "transition_run_id"))
    end
    assert_not operation.accepted_comparison?
  end

  test "source configuration changes invalidate current acceptance without erasing the audit" do
    @website.update!(default_language: "en")
    assert_not operation.accepted_comparison?
    assert_match /configuration changed/, operation.comparison.blockers.join
    assert_equal "Reviewed title and redirect", operation.activation.reason
  end

  test "a newer failed fetch is shown separately from the accepted comparison" do
    @cache.update!(scrape_date: 1.minute.from_now, health_status: "network_failed",
      signals: { transport_success: false, fetch_backend: "native" })
    assert operation.accepted_comparison?
    observed = operation.observed_fetch
    assert observed[:failed]
    assert_equal "Latest observed fetch failed", observed[:label]
    assert_equal @url, observed[:url]
    assert_equal "native", observed[:backend]
  end

  test "native fetch and redirected URL are visible while unexpected legacy use is flagged" do
    @cache.update!(scrape_date: 1.minute.from_now, health_status: "healthy", redirected: true,
      final_url: "https://example.org/final", signals: { fetch_backend: "native", transport_success: true, content_success: true })
    assert operation.observed_fetch[:redirected]
    assert_equal "https://example.org/final", operation.observed_fetch[:final_url]
    assert_not operation.observed_fetch[:failed]
    @cache.update!(signals: { fetch_backend: "legacy" })
    assert_match /did not use/, operation.observed_fetch[:label]
  end

  test "rollback and a new override activation do not reuse a previous review" do
    @website.rollout_events.create!(from_mode: "active", to_mode: "legacy", reason: "Rollback", readiness_snapshot: {})
    @website.rollout_events.create!(from_mode: "legacy", to_mode: "active", reason: "Override", readiness_snapshot: { override: true })
    assert_not operation.accepted_comparison?
    assert_equal "Activated with override", Distillator::WebsiteOperationStatus.event_label(operation.activation)
  end

  test "statement problems count selected statements including page overrides and exclude archived pages" do
    source = @website.sources.create!(algorithm_value: "xpath=//title", language: "fr", selected: true, property: properties(:one))
    alternative = @website.sources.create!(algorithm_value: "manual=other", language: "fr", selected: false, property: properties(:one))
    unselected = @website.sources.create!(algorithm_value: "manual=unused", language: "fr", selected: true, property: properties(:one))
    page = @website.webpages.first
    another_page = @website.webpages.create!(url: "https://example.org/another", language: "fr",
      rdf_uri: "rdf:another-operation-event", rdfs_class: rdfs_classes(:one))
    archived = @website.webpages.create!(url: "https://example.org/old", language: "fr", archive_date: 1.day.ago,
      rdf_uri: "rdf:archived-operation-event", rdfs_class: rdfs_classes(:one))
    Statement.create!(source: source, webpage: page, selected_individual: true, status: "problem")
    Statement.create!(source: source, webpage: another_page, selected_individual: true, status: "missing")
    Statement.create!(source: unselected, webpage: page, selected_individual: false, status: "problem")
    Statement.create!(source: alternative, webpage: page, selected_individual: true, status: "problem")
    Statement.create!(source: source, webpage: archived, selected_individual: true, status: "problem")
    assert_equal({ "problem" => 2, "missing" => 1 }, operation.statement_counts)
  end

  test "completed comparison is historical while a newer attempt keeps current activation gated" do
    run = Distillator::TransitionRun.request!(website: @website).run
    run.update!(status: "running", started_at: Time.current)
    @cache.update!(scrape_date: 1.second.from_now, signals: { transport_success: false })
    status = operation
    assert status.reviewed_completed_comparison?
    assert_not status.accepted_comparison?
    assert_equal :passed, status.completed_comparison.fetch
    assert_equal :failed, Distillator::TransitionStatus.call(website: @website, cache: @cache).fetch
    assert_includes status.comparison.blockers.join, "running"
    assert_equal "active", @website.reload.distillator_mode
    assert_raises(ArgumentError) { Distillator::TransitionStatus.for_completed_run(website: @website, run: run) }
    assert_raises(ArgumentError) { Distillator::TransitionStatus.for_completed_run(website: websites(:one), run: @run) }
    assert_raises(ArgumentError) { Distillator::TransitionStatus.for_completed_run(website: @website, run: nil) }
  end

  test "same mode settings saves do not become fake activations or erase the reviewed decision" do
    activation = operation.activation
    assert_no_difference "Distillator::RolloutEvent.count" do
      assert Distillator::RolloutTransition.call(website: @website, to_mode: "active").success?
    end
    assert_equal activation.id, operation.activation.id
    assert operation.accepted_comparison?
    @website.update!(graph_name: "https://example.org/changed")
    assert_not operation.accepted_comparison?
    assert operation.reviewed_completed_comparison?
  end

  test "report cannot mix a run that completes between loading the attempt and reading its evidence" do
    pending = Distillator::TransitionRun.request!(website: @website).run
    old_run = @run
    @website.define_singleton_method(:latest_transition_run) do
      observed = super()
      # Publish via another model instance after taking the attempt snapshot.
      Distillator::TransitionRun.find(pending.id).execute do |publishing|
        old_run.transition_evidences.each do |record|
          attrs = record.attributes.except("id", "created_at", "updated_at", "transition_run_id")
          publishing.transition_evidences.create!(attrs.merge("status" => "failed", "checked_at" => Time.current))
        end
      end
      observed
    end
    report = Distillator::ShadowSiteDetail.call(website: @website)
    assert_equal "completed", pending.reload.status
    assert_equal "queued", report.transition_run_status
    assert_equal @run.id, report.completed_transition_run_id
    assert_equal [@run.id], report.transition_evidence_by_kind.values.map(&:transition_run_id).uniq
    assert_equal :passed, report.completed_transition_status.statements
    assert report.operation_status.reviewed_completed_comparison?
    assert_equal "active", @website.reload.distillator_mode

    fresh = Distillator::ShadowSiteDetail.call(website: Website.find(@website.id))
    assert_equal pending.id, fresh.completed_transition_run_id
    assert_equal [pending.id], fresh.transition_evidence_by_kind.values.map(&:transition_run_id).uniq
    assert_equal :failed, fresh.completed_transition_status.statements
    assert_not fresh.operation_status.reviewed_completed_comparison?
  end

  private

  def operation
    Distillator::WebsiteOperationStatus.new(website: @website.reload, cache: @cache.reload)
  end
end
