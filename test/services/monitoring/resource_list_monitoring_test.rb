require "test_helper"

class ResourceListMonitoringTest < ActiveJob::TestCase
  setup do
    @old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    travel_to Time.zone.local(2026, 11, 24, 10)
    @site = Website.create!(seedurl: "resource-monitor", name: "Resource monitor", graph_name: "https://example.org/calendar",
      default_language: "en", monitorable: true, schedule_every_days: 1, schedule_time: Time.current, last_refresh: 1.day.ago)
    resource_list = RdfsClass.create!(name: "ResourceList")
    @list = @site.webpages.create!(url: "https://example.org/calendar", rdf_uri: "test:calendar", rdfs_class: resource_list, language: "en")
    klass = source(@list, AddWebpagesJob::RDF_CLASS_LABEL, "manual=Event")
    @list.statements.create!(source: klass, selected_individual: true, manual: true, status: "initial",
      status_origin: "condenser_refresh", cache: "Event")
    @url_list = payload(AddWebpagesJob::WEBPAGE_URL_LIST_LABEL)
    @uri_list = payload(AddWebpagesJob::URI_LIST_LABEL)
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_adapter
    travel_back
  end

  test "scheduled work tracks verified completion after import and distinguishes a failed extraction" do
    url = "https://example.org/event-new"
    stamp = scheduled
    assert_enqueued_with(job: RefreshWebpageJob, args: [@list.id, "resource_list", stamp.iso8601(6)])
    assert_nil state.completed_at
    publish_list_refresh(url)

    RefreshWebpageJob.perform_now(@list.id, "resource_list", stamp.iso8601(6))

    assert_equal Time.current, state.verified_at
    assert_nil state.completed_at
    perform_enqueued_jobs(only: AddWebpagesJob)
    assert_equal Time.current, state.completed_at
    assert @site.webpages.event_pages.exists?(url: url)
    assert_empty issues("resource_list_refresh")

    travel 1.day
    stamp = scheduled
    Distillator::RefreshRunner.expects(:call).returns([{ "Webpage URL List" => ["parse failed"] }])
    RefreshWebpageJob.perform_now(@list.id, "resource_list", stamp.iso8601(6))
    assert_includes issues("resource_list_refresh").sole.message, "could not be verified"
    assert_operator state.completed_at, :<, Time.current

    travel 1.day
    stamp = scheduled
    publish_list_refresh(url)
    RefreshWebpageJob.perform_now(@list.id, "resource_list", stamp.iso8601(6))
    perform_enqueued_jobs(only: AddWebpagesJob)
    assert_empty issues("resource_list_refresh")
  end

  test "audit distinguishes overdue refresh, overdue import and unpublishable listed events" do
    stamp = scheduled
    travel 5.hours
    Monitoring::ResourceListAudit.call
    assert_empty issues("resource_list_refresh")
    travel 2.hours
    Monitoring::ResourceListAudit.call
    assert_match "refresh is overdue", issues("resource_list_refresh").sole.message

    url = "https://example.org/listed"
    save_snapshot([url])
    observation = Monitoring::ResourceListRefresh.refreshed(@list, scheduled_at: stamp, started_at: Time.current)
    assert_empty issues("resource_list_refresh")
    Monitoring::ResourceListAudit.call
    assert_match "import is overdue", issues("resource_list_import_incomplete").sole.message

    travel 1.second
    Monitoring::ResourceListRefresh.imported(@list, observation, contents_digest: state.contents_digest)
    assert_includes issues("resource_list_import_incomplete").sole.message, "missing from Condenser"
    refute state.completed_at
    page = event(url)
    Monitoring::ResourceListRefresh.imported(@list, observation, contents_digest: state.contents_digest)
    assert_empty issues("resource_list_import_incomplete")
    Monitoring::ResourceListAudit.call
    assert_empty issues("listed_event_unpublishable")

    travel 7.hours
    Monitoring::ResourceListAudit.call
    assert_equal [page.url], issues("listed_event_unpublishable").sole.evidence.fetch("example_urls")
    page.update!(archive_date: 1.day.ago)
    Monitoring::ResourceListAudit.call
    assert_empty issues("listed_event_unpublishable")
  end

  test "audit flags a silent scheduler independent of website last_refresh" do
    Monitoring::ResourceListAudit.call
    assert_empty issues("resource_list_refresh")
    travel 31.hours
    @site.update!(last_refresh: Time.current)
    Monitoring::ResourceListAudit.call
    assert_includes issues("resource_list_refresh").sole.message, "overdue"
    Monitoring::ResourceListAudit.call
    assert_equal 1, issues("resource_list_refresh").sole.occurrences
  end

  test "only a verified archived reappearance queues a bounded probe and future evidence is resolved by a confirmed correction" do
    archived = event("https://example.org/archived", archive_date: 1.month.ago)
    current = event("https://example.org/current")
    dates = source(archived, "Dates", "xpath=//time/@datetime", value_datatype: "xsd:dateTime")

    observe_and_import([current.url, archived.url])
    travel 1.day
    observe_and_import([current.url, archived.url])
    assert_no_enqueued_jobs(only: ArchivedEventProbeJob)
    travel 1.day
    observe_and_import([current.url])
    assert_no_enqueued_jobs(only: ArchivedEventProbeJob)
    travel 1.day
    observe_and_import([current.url, archived.url])
    assert_enqueued_jobs 1, only: ArchivedEventProbeJob
    assert_equal 1, state.reappearances
    assert_empty issues("possible_missed_event")

    observed = 3.weeks.from_now
    original = archived.archive_date
    Monitoring::ArchivedEventDates.expects(:call).with(archived)
      .returns(Monitoring::ArchivedEventDates::Result.new(date: observed, source_id: dates.id)).once
    stamp = state.verified_at.iso8601(6)
    2.times { ArchivedEventProbeJob.perform_now(state.id, stamp) }
    issue = issues("possible_missed_event").sole
    assert_equal 1, issue.occurrences
    assert_equal observed, Time.iso8601(issue.evidence.fetch("observed_date"))
    assert_equal original, archived.reload.archive_date
    assert_equal "legacy", @site.reload.distillator_mode

    travel 1.hour
    archived.update!(archive_date: observed - 24.hours)
    Monitoring::ResourceListAudit.call
    assert_equal 1, issues("possible_missed_event").count
    archived.statements.create!(source: dates, status: "updated", cache: [observed.iso8601].to_json, cache_refreshed: Time.current)
    Monitoring::ResourceListAudit.call
    assert_empty issues("possible_missed_event")
  end

  private

  def state
    ResourceListMonitoringState.find_by!(webpage_id: @list.id)
  end

  def scheduled
    BatchJobsController.new.check_for_new_webpages_jobs(@site.seedurl, scheduled: true)
    state.scheduled_at
  end

  def issues(kind)
    MonitoringIssue.open_issues.where(kind: kind, seedurl: @site.seedurl)
  end

  def event(url, archive_date: 1.month.from_now)
    @site.webpages.create!(url: url, rdf_uri: "test:#{url.split('/').last}", language: "en",
      rdfs_class: rdfs_classes(:one), archive_date: archive_date)
  end

  def source(page, label, algorithm, value_datatype: nil)
    property = Property.create!(rdfs_class: page.rdfs_class, label: label, value_datatype: value_datatype,
      uri: "https://example.org/property/#{label.parameterize}")
    @site.sources.create!(property: property, selected: true, language: "en", algorithm_value: algorithm)
  end

  def payload(label)
    @list.statements.create!(source: source(@list, label, "xpath=//li/text()"), status: "ok", selected_individual: true)
  end

  def save_snapshot(urls)
    @url_list.update_columns(cache: urls.to_json, status: "updated", cache_refreshed: Time.current)
    @uri_list.update_columns(cache: urls.map { |url| "test:#{url.split('/').last}" }.to_json,
      status: "updated", cache_refreshed: Time.current)
  end

  def publish_list_refresh(url)
    Distillator::RefreshRunner.expects(:call).with { |args| args[:webpage].id == @list.id }
      .returns([]).once
    save_snapshot([url])
  end

  def observe_and_import(urls)
    stamp = scheduled
    save_snapshot(urls)
    observation = Monitoring::ResourceListRefresh.refreshed(@list, scheduled_at: stamp, started_at: Time.current)
    Monitoring::ResourceListRefresh.imported(@list, observation, contents_digest: state.contents_digest)
  end
end
