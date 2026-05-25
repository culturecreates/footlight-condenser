require "test_helper"

class Distillator::OperatorNextActionTest < ActiveSupport::TestCase
  test "blocked site says review blocker" do
    website = stub_website("shadow")
    status = stub_status(status: :blocked, blockers: ["Cannot activate yet: fetch check failed."])

    assert_equal "Review blocker.", Distillator::OperatorNextAction.call(website: website, transition_status: status)
  end

  test "legacy site says move to shadow" do
    website = stub_website("legacy")
    status = stub_status(status: :not_checked)

    assert_equal "Move to Shadow.", Distillator::OperatorNextAction.call(website: website, transition_status: status)
  end

  test "shadow site with stale evidence says run transition check" do
    website = stub_website("shadow")
    status = stub_status(status: :review, fetch: :stale)

    assert_equal "Run transition check.", Distillator::OperatorNextAction.call(website: website, transition_status: status)
  end

  test "ready shadow site says promote to active" do
    website = stub_website("shadow")
    status = stub_status(status: :ready)

    assert_equal "Promote to Active.", Distillator::OperatorNextAction.call(website: website, transition_status: status)
  end

  test "review-eligible shadow site says activate after review" do
    website = stub_website("shadow")
    status = stub_status(status: :review, review_activation_eligible: true)

    assert_equal "Activate after review.", Distillator::OperatorNextAction.call(website: website, transition_status: status)
  end

  test "ready active site prefers active cache when available" do
    website = stub_website("active")
    status = stub_status(status: :ready)

    assert_equal "Open active cache.", Distillator::OperatorNextAction.call(
      website: website,
      transition_status: status,
      cache_link_payload: { active_cache_url: "/condenser/cache?term=test" }
    )
  end

  test "ready active site falls back to monitor without cache link" do
    website = stub_website("active")
    status = stub_status(status: :ready)

    assert_equal "Monitor.", Distillator::OperatorNextAction.call(website: website, transition_status: status)
  end

  private

  def stub_website(mode)
    Struct.new(:distillator_mode).new(mode)
  end

  def stub_status(status:, blockers: [], fetch: :passed, statements: :passed, export: :passed, review_activation_eligible: false)
    Struct.new(:status, :blockers, :fetch, :statements, :export, :review_activation_eligible).new(status, blockers, fetch, statements, export, review_activation_eligible)
  end
end
