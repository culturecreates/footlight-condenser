module TransitionRunFixtures
  def publish_unavailable_source_run(website, url:, native_code: 404, legacy_code: 404)
    run = Distillator::TransitionRun.request!(website: website, options: { sample_mode: "all", strictness: "strict" }).run
    run.execute do
      urls = website.webpages.order(:id).pluck(:url)
      scope = { representative_webpages: urls, representative_webpage_count: urls.length,
        publishable_event_page_count: website.webpages.publishable.count, candidate_webpage_count: urls.length }
      rows = urls.map do |item|
        missing = item == url
        { url: item, attempted_condenser_fetch: true, fetch_status: missing ? "failed" : "passed",
          http_response_code: missing ? native_code : 200, condenser_fetch: { cache_hit: false },
          fetch_reason: missing ? "http_#{native_code}" : "ok", legacy_lookup_status: missing ? "unreachable" : "ok",
          legacy_fetch: { force_scrape: true, response_http_code: 200, upstream_http_code: missing ? legacy_code : 200 },
          comparison_status: missing ? "missing" : "passed", compare_missing: { legacy: missing, condenser: missing } }
      end
      run.transition_evidences.create!(website: website, url: url, check_kind: "fetch_parity", status: "failed", checked_at: Time.current,
        details: scope.merge(fetch_basis: "fresh_both", reason: "http_#{native_code}", representative_url_results: rows))
      run.transition_evidences.create!(website: website, url: url, check_kind: "statement_delta", status: "pending", checked_at: Time.current,
        details: scope.merge(reason: "partial_fetch_failed_before_statement_refresh", compared_webpage_count: urls.length - 1))
      run.transition_evidences.create!(website: website, url: url, check_kind: "export_diff", status: "pending", checked_at: Time.current,
        details: scope.merge(reason: "partial_fetch_failed_before_export_comparison"))
    end
    run
  end

  # Policy unit tests supply phase evidence directly; run publication is covered
  # separately by TransitionRunTest and P1PersistenceTest.
  def isolate_transition_policy(website)
    website.stubs(:transition_run_blocker).returns(nil)
    website.define_singleton_method(:latest_transition_evidences_by_kind) do
      transition_evidences.latest_first.each_with_object({}) { |record, out| out[record.check_kind] ||= record }
    end
    website
  end

  # Build one published attempt for report/activation fixtures. Unspecified phases
  # are pending, never implicitly passing. Preserve older records for stale tests.
  def publish_transition_fixture(website, defaults: {}, at: Time.current)
    records = website.transition_evidences.where(transition_run_id: nil).to_a
    run = website.transition_runs.create!(status: "completed", requested_at: at, started_at: at,
      completed_at: at, configuration_digest: Distillator::TransitionFingerprint.call(website))
    records.each { |record| record.update_column(:transition_run_id, run.id) }
    Distillator::TransitionEvidence::REPORT_CHECK_KINDS.each do |kind|
      next if records.any? { |record| record.check_kind == kind }
      run.transition_evidences.create!({ website: website, url: "https://example.org/#{website.seedurl}",
        check_kind: kind, status: "pending", checked_at: at }.merge(defaults.fetch(kind, {})))
    end
    run
  end
end

ActiveSupport::TestCase.include TransitionRunFixtures
