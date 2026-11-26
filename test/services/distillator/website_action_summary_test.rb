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

    test "failed recovery appears ahead of an unverified list" do
      @validation.attention = SiteTransition.new(status: "recovery_failed", reason: "Recovery could not be confirmed")
      @inventory[:lists] = [{ status: "unverified", reason: :invalid_or_empty_list, message: "Invalid URLs", webpage_id: 1, next_action: :inspect_extraction }]
      assert_equal %i[recovery_failed invalid_or_empty_list], actions.map(&:code)
      assert_equal %i[p0 p1], actions.map(&:priority)
    end

    test "legacy staging redirects to website diagnostics and idle sites generate no incident" do
      @site.distillator_mode = "legacy"
      assert_equal :staging_mode, actions(staging: true).sole.code
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
