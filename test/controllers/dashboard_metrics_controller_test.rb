require "test_helper"

class DashboardMetricsControllerTest < ActionDispatch::IntegrationTest
  test "schedule overdue relies on observed list completion and the target website schedule" do
    travel_to Time.zone.local(2026, 11, 24, 10) do
      late = website("metrics-late")
      on_time = website("metrics-on-time")
      pending = website("metrics-pending")
      missing = website("metrics-missing")
      unscheduled = website("metrics-unscheduled", schedule_every_days: 0)
      resource_list(late, scheduled_at: 7.hours.ago)
      resource_list(late, completed_at: 1.hour.ago)
      resource_list(on_time, completed_at: 1.hour.ago, owner: unscheduled)
      resource_list(pending, scheduled_at: 1.hour.ago)
      resource_list(unscheduled, completed_at: 1.week.ago)

      Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
      get "/dashboard_metrics"

      assert_response :success
      metrics = response.parsed_body
      assert_equal 1, metrics.dig(late.seedurl, "days_overdue")
      assert_equal 0, metrics.dig(on_time.seedurl, "days_overdue")
      [pending, missing, unscheduled].each do |site|
        assert_nil metrics.fetch(site.seedurl).fetch("days_overdue")
      end
    end
  end

  test "horizon uses Event pages and cached metrics retain their original timestamp" do
    travel_to Time.zone.local(2026, 11, 24, 10) do
      past = website("metrics-past")
      no_events = website("metrics-no-events")
      past.webpages.create!(url: "https://example.org/old-event", rdf_uri: "test:old-event",
        language: "en", rdfs_class: rdf_class("Event"), archive_date: 2.days.ago, created_at: 8.days.ago)
      resource_list(past, archive_date: 1.year.from_now)
      resource_list(no_events, archive_date: 1.year.from_now)
      Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)

      get "/dashboard_metrics"
      assert_response :success
      snapshot = response.parsed_body
      assert_equal(-2, snapshot.dig(past.seedurl, "event_horizon_days"))
      assert_nil snapshot.fetch(no_events.seedurl).fetch("event_horizon_days")
      assert_equal Time.current.iso8601, snapshot.dig(past.seedurl, "data_as_of")

      travel 1.minute
      get "/dashboard_metrics"
      assert_equal snapshot.dig(past.seedurl, "data_as_of"), response.parsed_body.dig(past.seedurl, "data_as_of")

      get "/dashboard_metrics/broken"
      assert_response :success
      assert response.parsed_body.key?(past.seedurl)
      refute response.parsed_body.key?(no_events.seedurl)
    end
  end

  private

  def website(seedurl, schedule_every_days: 1)
    Website.create!(seedurl: seedurl, name: seedurl, graph_name: "https://example.org/#{seedurl}",
      default_language: "en", monitorable: true, schedule_every_days: schedule_every_days,
      schedule_time: Time.current, last_refresh: Time.current)
  end

  def rdf_class(name)
    RdfsClass.find_by(name: name) || RdfsClass.create!(name: name)
  end

  def resource_list(target, owner: target, archive_date: nil, **state)
    url = "https://example.org/#{owner.seedurl}/list-#{owner.webpages.count}"
    page = owner.webpages.create!(url: url, rdf_uri: url, language: "en", rdfs_class: rdf_class("ResourceList"),
      archive_date: archive_date, discovery_target_website: (target unless target == owner))
    ResourceListMonitoringState.create!(webpage: page, website: target, **state) if state.any?
    page
  end
end
