module TransitionRunFixtures
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
