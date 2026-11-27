require "test_helper"

class AddWebpagesJobTest < ActiveJob::TestCase
  setup do
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @resource_list_page = webpages(:resource_list_page)
    @rdf_class_statement = statements(:resource_list_rdf_class_statement)
    @uri_list_statement = statements(:resource_list_uri_list_statement)
    @url_list_statement = statements(:resource_list_url_list_statement)
    @resource_list_page.update!(rdfs_class: RdfsClass.find_or_create_by!(name: "ResourceList"))

    sources(:resource_list_rdf_class_source).property.update!(label: AddWebpagesJob::RDF_CLASS_LABEL)
    sources(:resource_list_uri_list_source).property.update!(label: AddWebpagesJob::URI_LIST_LABEL)
    sources(:resource_list_url_list_source).property.update!(label: AddWebpagesJob::WEBPAGE_URL_LIST_LABEL)
    [@uri_list_statement, @url_list_statement].each do |statement|
      statement.source.update!(algorithm_value: "xpath=//li/text()")
      statement.update_columns(cache_refreshed: Time.current)
    end
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_queue_adapter
  end

  test "valid list creates webpages and enqueues refreshes" do
    assert_difference("Webpage.count", 2) do
      AddWebpagesJob.perform_now(@resource_list_page.url)
    end

    assert_equal 2, enqueued_jobs.count { |job| job[:job] == RefreshWebpageJob }
    assert Webpage.exists?(url: "https://example.org/events/1", website: @resource_list_page.website)
    assert Webpage.exists?(url: "https://example.org/events/2", website: @resource_list_page.website)
  end

  test "QA copied ResourceList rejects original-site RDF URIs at import" do
    copy = Website.create!(name: "Danse Danse QA", seedurl: "dansedansetest-ca",
      graph_name: "https://example.org/dansedansetest-ca", default_language: "fr",
      test_copy_of_website: @resource_list_page.website)
    cloned_page = copy.webpages.create!(url: @resource_list_page.url,
      rdf_uri: "http://kg.footlight.io/resource/dansedansetest-ca_rl",
      language: @resource_list_page.language, rdfs_class: @resource_list_page.rdfs_class)
    [@rdf_class_statement, @uri_list_statement, @url_list_statement].each do |original|
      cloned_source = original.source.dup
      cloned_source.website = copy
      cloned_source.save!
      cloned_page.statements.create!(source: cloned_source, cache: original.cache,
        status: "ok", selected_individual: true, manual: true)
    end

    assert_no_difference("Webpage.count") do
      error = assert_raises(AddWebpagesJob::InvalidResourceListError) do
        AddWebpagesJob.perform_now(cloned_page.id, refresh_new: false)
      end
      assert_match(/outside the copied website namespace/, error.message)
    end
  end

  test "scheduled discovery imports a linked Event ResourceList into its target website" do
    owner = @resource_list_page.website
    target = Website.create!(name: "Event target", seedurl: "target", graph_name: "https://example.org/target", default_language: "en")
    @resource_list_page.update!(rdfs_class: RdfsClass.find_or_create_by!(name: "ResourceList"), discovery_target_website: target)
    assert_no_enqueued_jobs(only: RefreshWebpageJob) { BatchJobsController.new.check_for_new_webpages_jobs(owner.seedurl) }
    assert_enqueued_with(job: RefreshWebpageJob, args: [@resource_list_page.id, "resource_list"]) do
      BatchJobsController.new.check_for_new_webpages_jobs(target.seedurl)
    end

    assert_difference("Webpage.count", 2) { AddWebpagesJob.perform_now(@resource_list_page.id) }
    assert_empty owner.webpages.where(url: "https://example.org/events/1")
    created = target.webpages.find_by!(url: "https://example.org/events/1")
    assert_enqueued_with(job: RefreshWebpageJob, args: [created.id])
  end

  test "Danse Danse French equivalent initial and updated manual declarations import with a warning" do
    @rdf_class_statement.update_columns(status: "initial", manual: true, cache_refreshed: nil)
    equivalent = @rdf_class_statement.source.dup
    equivalent.save!
    @resource_list_page.statements.create!(source: equivalent, cache: "Event", status: "updated", manual: true, selected_individual: true)

    assert_equal "duplicate_discovery_class_declarations", inventory_for_list.fetch(:warning)
    assert_equal "event", inventory_for_list.fetch(:status)
    assert_difference("Webpage.count", 2) { AddWebpagesJob.perform_now(@resource_list_page.id, selected_only: true, refresh_new: false) }
    assert_equal "initial", @rdf_class_statement.reload.status
  end

  test "Danse Danse English and Vieux Noranda initial declarations need no review or class refresh" do
    @rdf_class_statement.update_columns(status: "initial", manual: true, cache_refreshed: nil)

    assert_equal "event", inventory_for_list.fetch(:status)
    assert_difference("Webpage.count", 2) { AddWebpagesJob.perform_now(@resource_list_page.id) }
    assert_equal "initial", @rdf_class_statement.reload.status
    assert_nil @rdf_class_statement.cache_refreshed
  end

  test "Co-motion a recently refreshed initial class cannot make old list contents fresh" do
    @rdf_class_statement.update_columns(status: "initial", manual: true, cache_refreshed: Time.current)
    travel 3.days do
      @rdf_class_statement.update_columns(cache_refreshed: Time.current)
      assert_equal "stale_list", inventory_for_list.fetch(:reason)
    end
  end

  test "an initial or manually overridden list payload stays unverified" do
    [@uri_list_statement, @url_list_statement].each do |payload|
      payload.update_columns(status: "initial")
      assert_equal "unreviewed_discovery_list", inventory_for_list.fetch(:reason)
      payload.update_columns(status: "ok", manual: true)
      assert_equal "manual_discovery_list_override", inventory_for_list.fetch(:reason)
      payload.update_columns(manual: false)
    end
    assert_equal "event", inventory_for_list.fetch(:status)
    @url_list_statement.source.update!(algorithm_value: "manual=#{@url_list_statement.cache}")
    @url_list_statement.update_columns(cache_refreshed: Time.current)
    assert_equal "fixed_discovery_list_payload", inventory_for_list.fetch(:reason)
  end

  test "discovery and inventory report the same class configuration errors" do
    @rdf_class_statement.source.update!(selected: false)
    assert_class_rejected("unselected_discovery_class")

    @rdf_class_statement.source.update!(selected: true, algorithm_value: "manual=Place")
    assert_class_rejected("mismatched_manual_discovery_class")

    @rdf_class_statement.source.update!(algorithm_value: "manual=Event")
    conflict = @rdf_class_statement.source.dup
    conflict.update!(algorithm_value: "manual=None")
    @resource_list_page.statements.create!(source: conflict, cache: "None", status: "initial", manual: true, selected_individual: true)
    assert_class_rejected("conflicting_discovery_classes")
  end

  test "fixed valid non-event classes are excluded from event inventory and retain normal discovery" do
    @rdf_class_statement.source.update!(algorithm_value: "manual=Place")
    @rdf_class_statement.update_columns(cache: "Place", status: "initial", manual: true)

    assert_equal "other_class", inventory_for_list.fetch(:status)
    ids = AddWebpagesJob.perform_now(@resource_list_page.id, selected_only: true, refresh_new: false)
    assert_equal ["Place"], Webpage.where(id: ids).map { |page| page.rdfs_class.name }.uniq
  end

  test "valid empty extracted event list has a digest and imports no webpages" do
    [@url_list_statement, @uri_list_statement].each do |row|
      row.update_columns(cache: "[]", status: "updated", selected_individual: true, cache_refreshed: Time.current)
    end
    snapshot = inventory_for_list
    assert_equal "event", snapshot.fetch(:status)
    assert_equal 0, snapshot.fetch(:count)
    assert_equal Distillator::TransitionEventInventory.list_digest([], []), snapshot.fetch(:contents_digest)
    assert_no_difference("Webpage.count") do
      assert_no_enqueued_jobs(only: RefreshWebpageJob) do
        AddWebpagesJob.perform_now(@resource_list_page.id, selected_only: true)
      end
    end
  end

  test "empty URL List and nonempty URI List remains invalid" do
    @url_list_statement.update_columns(cache: "[]", status: "updated", cache_refreshed: Time.current)
    assert_equal "invalid_or_empty_list", inventory_for_list.fetch(:reason)
    assert_raises(AddWebpagesJob::InvalidResourceListError) { AddWebpagesJob.perform_now(@resource_list_page.id) }
  end

  test "missing approved extraction cannot masquerade as empty" do
    @url_list_statement.update_columns(cache: "[]", status: "initial", cache_refreshed: Time.current)
    @uri_list_statement.update_columns(cache: "[]", status: "updated", cache_refreshed: Time.current)
    assert_equal "unreviewed_discovery_list", inventory_for_list.fetch(:reason)
  end

  test "mismatched uri and url counts creates none and raises" do
    @url_list_statement.update!(cache: '["https://example.org/events/1"]')

    assert_raises(AddWebpagesJob::InvalidResourceListError) do
      AddWebpagesJob.perform_now(@resource_list_page.url)
    end

    assert_equal 0, Webpage.where(url: ["https://example.org/events/1", "https://example.org/events/2"], website: @resource_list_page.website).count
    assert_equal 0, enqueued_jobs.count { |job| job[:job] == RefreshWebpageJob }
  end

  test "invalid json array creates none and raises" do
    @uri_list_statement.update!(cache: '{"uri":"adr:event-1"}')

    assert_raises(AddWebpagesJob::InvalidResourceListError) do
      AddWebpagesJob.perform_now(@resource_list_page.url)
    end

    assert_equal 0, Webpage.where(url: ["https://example.org/events/1", "https://example.org/events/2"], website: @resource_list_page.website).count
    assert_equal 0, enqueued_jobs.count { |job| job[:job] == RefreshWebpageJob }
  end

  test "blank or missing rdf class raises even without a uri list" do
    @uri_list_statement.destroy!
    @rdf_class_statement.update!(cache: "")

    error = assert_raises(AddWebpagesJob::InvalidResourceListError) do
      AddWebpagesJob.perform_now(@resource_list_page.url)
    end
    assert_equal "missing_discovery_class_value", error.message

    @rdf_class_statement.destroy!
    error = assert_raises(AddWebpagesJob::InvalidResourceListError) do
      AddWebpagesJob.perform_now(@resource_list_page.url)
    end
    assert_equal "missing_discovery_class", error.message

    assert_equal 0, Webpage.where(url: ["https://example.org/events/1", "https://example.org/events/2"], website: @resource_list_page.website).count
    assert_equal 0, enqueued_jobs.count { |job| job[:job] == RefreshWebpageJob }
  end

  test "a legacy job for a data-only list succeeds without a uri list or new webpages" do
    @rdf_class_statement.source.update!(algorithm_value: "manual=None")
    @rdf_class_statement.update!(cache: "None")
    @uri_list_statement.destroy!

    assert_no_difference("Webpage.count") do
      assert_no_enqueued_jobs(only: RefreshWebpageJob) { AddWebpagesJob.perform_now(@resource_list_page.url) }
    end

    assert_equal '["https://example.org/events/1","https://example.org/events/2"]', @url_list_statement.reload.cache
  end

  test "a scheduled data-only list refresh stores its inputs and targets the right website when URLs are shared" do
    data_website = websites(:one)
    resource_list_class = RdfsClass.find_by!(name: "ResourceList")
    page = Webpage.create!(url: @resource_list_page.url, rdf_uri: "adr:audience-list", website: data_website,
      rdfs_class: resource_list_class, language: "fr")
    class_property = Property.create!(label: AddWebpagesJob::RDF_CLASS_LABEL, rdfs_class: resource_list_class, uri: "urn:test:rdf-class")
    url_property = Property.create!(label: AddWebpagesJob::WEBPAGE_URL_LIST_LABEL, rdfs_class: resource_list_class, uri: "urn:test:url-list")
    urls = ["https://example.org/events?id_evenement=46721&audiences=3", "https://example.org/events?id_evenement=46545"]
    class_source = Source.create!(website: data_website, property: class_property, language: "fr", selected: true, algorithm_value: "manual=None")
    url_source = Source.create!(website: data_website, property: url_property, language: "fr", selected: true, algorithm_value: "manual=#{urls.to_json}")

    assert_no_difference("Webpage.count") do
      perform_enqueued_jobs { BatchJobsController.new.check_for_new_webpages_jobs(data_website.seedurl) }
    end

    assert_performed_jobs 1, only: RefreshWebpageJob
    assert_performed_with(job: AddWebpagesJob, args: [page.id])
    assert_equal "None", page.statements.find_by!(source: class_source).cache
    assert_equal urls, JSON.parse(page.statements.find_by!(source: url_source).cache)
    assert_equal "Event", @rdf_class_statement.reload.cache

    assert_no_difference("Webpage.count") do
      error = assert_raises(AddWebpagesJob::InvalidResourceListError) { AddWebpagesJob.perform_now(page.url) }
      assert_match(/multiple webpages/, error.message)
    end
  end

  test "duplicate webpage does not duplicate or enqueue refresh twice" do
    Webpage.create!(
      url: "https://example.org/events/1",
      rdf_uri: "adr:event-1",
      language: @resource_list_page.language,
      rdfs_class: rdfs_classes(:one),
      website: @resource_list_page.website
    )

    assert_difference("Webpage.count", 1) do
      AddWebpagesJob.perform_now(@resource_list_page.url)
    end

    assert_equal 1, Webpage.where(url: "https://example.org/events/1", website: @resource_list_page.website).count
    assert_equal 1, enqueued_jobs.count { |job| job[:job] == RefreshWebpageJob }
    assert Webpage.exists?(url: "https://example.org/events/2", website: @resource_list_page.website)
  end
  private

  def inventory_for_list
    website = @resource_list_page.website
    Distillator::TransitionEventInventory.new(as_of: Time.current).for_websites([website.id],
      events: website.webpages.public_publishable_events.active).fetch(website.id).lists.find do |list|
      list[:webpage_id] == @resource_list_page.id
    end
  end

  def assert_class_rejected(reason)
    assert_equal reason, inventory_for_list.fetch(:reason)
    assert_no_difference("Webpage.count") do
      error = assert_raises(AddWebpagesJob::InvalidResourceListError) { AddWebpagesJob.perform_now(@resource_list_page.id) }
      assert_equal reason, error.message
    end
  end

end
