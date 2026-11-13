require "test_helper"

class DistillatorPhase1StagingPlanTest < ActiveSupport::TestCase
  PLAN_PATH = Rails.root.join("docs", "distillator_phase1_full_migration_staging_plan.md")
  REPORT_PATH = Rails.root.join("docs", "distillator_phase1_staging_acceptance_report.md")

  REQUIRED_ENDPOINTS = [
    "GET /websites/wring?uri=<known-url>&format=raw",
    "GET /websites/wring?uri=<known-url>&format=json",
    "GET /websites.json?term=<escaped-uri>"
  ].freeze

  test "staging plan and acceptance report exist" do
    assert File.exist?(PLAN_PATH), "Expected #{PLAN_PATH} to exist"
    assert File.exist?(REPORT_PATH), "Expected #{REPORT_PATH} to exist"
  end

  test "staging plan references readiness document" do
    plan = File.read(PLAN_PATH)

    assert_includes plan, "distillator_phase1_wringer_readiness.md"
    assert_includes plan, "Distillator Phase 1 Wringer Readiness"
  end

  test "staging plan references required endpoints" do
    plan = File.read(PLAN_PATH)

    REQUIRED_ENDPOINTS.each do |endpoint|
      assert_includes plan, endpoint
    end
  end

  test "staging plan includes rollback section" do
    plan = File.read(PLAN_PATH)

    assert_match(/^## Rollback$/, plan)
    assert_includes plan, "Route traffic back to old Wringer"
    assert_includes plan, "Unset any non-default fetch mode"
  end

  test "acceptance report includes decision field" do
    report = File.read(REPORT_PATH)

    assert_match(/^## Decision$/, report)
    assert_includes report, "Decision: accept / reject / accept with follow-ups"
  end
end
