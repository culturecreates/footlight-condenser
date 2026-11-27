require "test_helper"

class Distillator::P1PersistenceTest < ActiveSupport::TestCase
  test "audit write failure rolls back the production mode" do
    website = site("atomic-audit")
    Distillator::RolloutEventRecorder.stubs(:call).raises(RuntimeError, "simulated audit failure")

    assert_raises(RuntimeError) { Distillator::RolloutTransition.call(website: website, to_mode: "shadow") }

    assert_equal "legacy", website.reload.distillator_mode
    assert_equal 0, website.rollout_events.count
  end

  test "successful mode change and audit commit together" do
    website = site("atomic-success")
    result = Distillator::RolloutTransition.call(website: website, to_mode: "shadow")

    assert result.success?
    assert_equal "shadow", website.reload.distillator_mode
    assert_equal ["legacy", "shadow"], website.rollout_events.last.attributes.values_at("from_mode", "to_mode")
  end

  test "historical unbound passing evidence cannot authorize activation" do
    website = site("historical-proof")
    website.update!(distillator_mode: "shadow")
    Distillator::TransitionEvidence::REPORT_CHECK_KINDS.each do |kind|
      website.transition_evidences.create!(url: "https://example.org/event", check_kind: kind, status: "checked", checked_at: Time.current,
        statement_count_delta_acceptable: true, export_diff_checked: true)
    end
    result = Distillator::RolloutTransition.call(website: website, to_mode: "active")
    assert_not result.success?
    assert_equal "shadow", website.reload.distillator_mode
    assert_empty website.latest_transition_evidences_by_kind
  end

  private

  def site(slug)
    Website.create!(name: slug, seedurl: slug, graph_name: "https://example.org/#{slug}", default_language: "en", distillator_mode: "legacy")
  end
end

class Distillator::P1ConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "simultaneous mode changes preserve a continuous audit history" do
    website = Website.create!(name: "Concurrent modes", seedurl: "concurrent-modes-#{SecureRandom.hex(4)}",
      graph_name: "https://example.org/concurrent-modes", default_language: "en", distillator_mode: "active")
    start = Queue.new
    threads = %w[legacy shadow].map do |mode|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          copy = Website.find(website.id)
          start.pop
          Distillator::RolloutTransition.call(website: copy, to_mode: mode)
        end
      end
    end
    2.times { start << true }
    assert threads.map(&:value).all?(&:success?)
    history = website.rollout_events.order(:id).to_a
    assert_equal 2, history.length
    assert_equal "active", history.first.from_mode
    assert_equal history.first.to_mode, history.last.from_mode
    assert_equal history.last.to_mode, website.reload.distillator_mode
  ensure
    threads&.each(&:join)
    website&.destroy!
  end

  test "simultaneous requests create only one active run" do
    website = Website.create!(name: "Concurrent run", seedurl: "concurrent-run-#{SecureRandom.hex(4)}",
      graph_name: "https://example.org/concurrent", default_language: "en", distillator_mode: "shadow")
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          copy = Website.find(website.id)
          start.pop
          Distillator::TransitionRun.request!(website: copy)
        end
      end
    end
    2.times { start << true }
    results = threads.map(&:value)
    assert_equal 1, results.count(&:created?)
    assert_equal 1, results.map { |result| result.run.id }.uniq.length
    assert_equal 1, website.transition_runs.active.count
  ensure
    threads&.each(&:join)
    website&.destroy!
  end
end
