require "test_helper"

module Distillator
  class WebsiteActionSummaryTest < ActiveSupport::TestCase
    setup do
      @site = websites(:one)
      @site.distillator_mode = "active"
      @inventory = { status: "confirmed_discovery", selected_event_urls_missing: 0, lists: [] }
      @validation = WebsiteValidationHistory::Summary.new(thorough: 1)
    end

    test "outdated Thorough evidence is work to repeat and verified discovery creates no reconciliation task" do
      @validation.latest_thorough = WebsiteValidationHistory::Pass.new(profile: "thorough", completed_at: 1.day.ago)
      @validation.changed = true
      @validation.milestone_reason = :discovery_configuration_changed
      outcome = actions.sole
      assert_equal :validation_outdated, outcome.code
      assert_equal :p2, outcome.priority
      assert outcome.matches?("attention")
      assert outcome.matches?("validation")
      assert_match(/Active to Shadow/, outcome.consequence)
      assert_no_match(/failed|reconciliation/i, outcome.explanation)
    end

    test "a listed event with missing Location takes precedence over validation" do
      uri = "urn:event-without-place"
      @inventory[:unpublishable_listed_pages] = [{ rdf_uri: uri }]
      requirements = [[[@site.id, uri], [{ field: "Location", reasons: ["Location value is empty or unusable"] }]]]
      outcome = actions(requirements: requirements).sole
      assert_equal :missing_event_fields, outcome.code
      assert_equal :p1, outcome.priority
      assert_equal :event_statements, outcome.operation
      assert_equal uri, outcome.evidence[:rdf_uri]
      assert_match(/Location unavailable/, outcome.explanation)
      assert_not outcome.matches?("validation")
    end

    test "missing field title and count summarize distinct affected event resources" do
      requirements = [[[@site.id, "urn:without-place"], [{ field: "Location", reasons: ["Missing Place"] }]],
        [[@site.id, "urn:without-dates"], [{ field: "Dates", reasons: ["Missing performance dates"] }]]]
      outcome = actions(requirements: requirements).find { |item| item.code == :missing_event_fields }
      assert_equal "Missing Dates and Location", outcome.title
      assert_equal 2, outcome.evidence[:event_count]
      assert_equal "urn:without-place", outcome.evidence[:rdf_uri]
    end

    test "a Ready site offers cutover and an already Migrated site has no recommendation" do
      @validation.milestone = "ready"
      assert_equal :confirm_cutover, actions.sole.operation
      assert actions.sole.matches?("migration")
      @validation.milestone = "migrated"
      assert_empty actions
    end

    test "an in-progress Active audit keeps the rollout mode and takes no cutover action" do
      @validation.milestone = "ready"
      item = SiteTransition.new(status: "running", batch: TransitionBatch.new(workflow_action: "audit"))
      outcome = actions(running: item).sole
      assert_equal :audit_in_progress, outcome.code
      assert_equal :workflow, outcome.operation
      assert_match(/keeps the current rollout mode/, outcome.impact)
      assert_not outcome.matches?("validation")
    end

    test "a queued or running comparison leads and earlier findings remain available" do
      @validation.attention = TransitionRun.new(status: "failed", error_message: "Previous comparison failed")
      @inventory[:lists] = [{ status: "unverified", webpage_id: 1, **ResourceListReadiness.guidance(:invalid_or_empty_list) }]

      %w[queued running].each do |status|
        outcomes = actions(running: TransitionRun.new(status: status))
        assert_equal %i[validation_in_progress invalid_or_empty_list comparison_failed], outcomes.map(&:code)
        assert_match(/previous run/, outcomes.last.title)
      end
    end

    test "failed recovery appears ahead of running work and an unverified list" do
      @validation.attention = SiteTransition.new(status: "recovery_failed", reason: "Recovery could not be confirmed")
      @inventory[:lists] = [{ status: "unverified", reason: :invalid_or_empty_list, message: "Invalid URLs", webpage_id: 1, next_action: :inspect_extraction }]
      outcomes = actions(running: TransitionRun.new(status: "running"))
      assert_equal %i[recovery_failed validation_in_progress invalid_or_empty_list], outcomes.map(&:code)
      assert_equal %i[p0 progress p1], outcomes.map(&:priority)
    end

    test "maintenance on a verified list remains diagnostic and preserves cutover eligibility" do
      @validation.milestone = "ready"
      list = { status: "event", webpage_id: 1, count: 4, new_count: 0 }
      extracted_at = 3.days.ago
      evidence = { fetch: { state: :stale, last_success_at: extracted_at }, extraction: { last_success_at: extracted_at } }
      @inventory[:lists] = ResourceListReadiness.for_lists([list], activity: { 1 => evidence })

      assert_equal :source_fetch_stale, @inventory[:lists].sole[:reason]
      assert_equal :healthy, @inventory[:lists].sole[:health]
      assert_equal :confirm_cutover, actions.sole.code

      evidence[:fetch] = { state: :fresh, last_success_at: 1.hour.ago }
      @inventory[:lists] = ResourceListReadiness.for_lists([list], activity: { 1 => evidence })
      assert_equal :extraction_predates_source, @inventory[:lists].sole[:reason]
      assert_equal :confirm_cutover, actions.sole.code

      evidence[:extraction][:last_success_at] = Time.current
      @inventory[:lists] = ResourceListReadiness.for_lists([list], activity: { 1 => evidence })
      assert_equal :confirm_cutover, actions.sole.code
    end

    test "unverified actual extraction failure remains a P1 action" do
      @inventory[:lists] = [{ status: "unverified", health: :failed, webpage_id: 4,
        **ResourceListReadiness.guidance(:invalid_list) }]
      assert_equal :invalid_list, actions.first.code
      assert_equal :p1, actions.first.priority
    end

    test "legacy staging redirects to website diagnostics and idle sites generate no incident" do
      @site.distillator_mode = "legacy"
      assert_equal :staging_mode, actions(staging: true).sole.code
      assert_equal :website, actions(staging: true, eligible: false).sole.operation
      @site.distillator_mode = nil
      assert_match(/unset or unsupported/, actions(staging: true, eligible: false).sole.explanation)
      assert_empty actions(eligible: false)
    end

    test "classification uses a fixed number of SQL queries across websites" do
      sites = Website.order(:id).to_a
      # Warm class metadata before measuring the bulk evidence requests.
      WebsiteActionSummary.running_for(sites.map(&:id))
      one = query_count_for(sites.first(1))
      many = query_count_for(sites)
      assert_equal one, many
    end

    private

    def query_count_for(sites)
      ids = sites.map(&:id)
      count = 0
      handler = ->(_name, _start, _finish, _id, data) { count += 1 unless data[:name].in?(%w[SCHEMA TRANSACTION]) || data[:cached] }
      ActiveRecord::Base.uncached do
        ActiveSupport::Notifications.subscribed(handler, "sql.active_record") do
          active = WebsiteActionSummary.running_for(ids)
          WebsiteActionSummary.for_websites(sites, inventories: ids.index_with { @inventory },
            validations: ids.index_with { @validation }, eligible_ids: ids, running: active)
        end
      end
      count
    end

    def actions(eligible: true, running: nil, requirements: [], staging: false)
      WebsiteActionSummary.new(@site, inventory: @inventory, validation: @validation,
        eligible: eligible, running: running, requirements: requirements, staging: staging).call
    end
  end
end
