require "test_helper"

class Distillator::P1NavigationTest < ActiveSupport::TestCase
  test "All modes includes Legacy Shadow and Active with complete filtered totals on every page" do
    %w[legacy shadow active].each do |mode|
      Website.create!(name: "P1 navigation #{mode}", seedurl: "p1-navigation-#{mode}", graph_name: "https://example.org/#{mode}", default_language: "en", distillator_mode: mode)
    end
    reports = [1, 2].map do |page|
      Distillator::ShadowReport.call(filters: { mode: "all", term: "p1-navigation" }, sort: "website", direction: "asc", page: page, per_page: 1)
    end
    reports.each do |report|
      assert_equal 1, report.rows.length
      assert_equal 3, report.total_count
      assert_equal 3, report.global_summary_counts[:total]
      assert_equal 1, report.dashboard_counts[:legacy_sites]
      assert_equal 1, report.dashboard_counts[:shadow_sites]
      assert_equal 1, report.dashboard_counts[:active_sites]
    end
  end

  test "comparison failures are counted by structured status rather than English text" do
    website = Website.create!(name: "P1 blocker", seedurl: "p1-blocker", graph_name: "https://example.org/blocker", default_language: "en", distillator_mode: "shadow")
    run = Distillator::TransitionRun.request!(website: website).run
    run.execute do
      %w[fetch_parity statement_delta export_diff].each do |kind|
        Distillator::TransitionEvidenceRecorder.call(website: website, transition_run: run, url: "https://example.org/event",
          check_kind: kind, status: kind == "fetch_parity" ? :failed : :pending,
          details: { reason: "cache_compare_blocking_regression" })
      end
    end
    report = Distillator::ShadowReport.call(filters: { mode: "all", term: "p1-blocker" }, sort: "website", direction: "asc", page: 1, per_page: 25)
    assert_equal 1, report.blocker_counts[:failed_fetch]
  end

  test "context includes multiword diagnostic actions" do
    helper = Object.new.extend(OperatorContextHelper)
    def helper.suppress_source_show_operator_context_domain?; false; end
    def helper.operator_context_url(**); nil; end
    links = ["Compare Condenser vs Wringer", "Inspect legacy Wringer", "Open Condenser cache"].map do |label|
      { label: label, url: "/diagnostics" }
    end
    assert_equal links, helper.operator_context_action_links(cache_links: { secondary_links: links })
  end
end
