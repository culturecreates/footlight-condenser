require "test_helper"

class AddWebpagesJobTest < ActiveJob::TestCase
  setup do
    @previous_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @resource_list_page = webpages(:resource_list_page)
    @rdf_class_statement = statements(:resource_list_rdf_class_statement)
    @uri_list_statement = statements(:resource_list_uri_list_statement)
    @url_list_statement = statements(:resource_list_url_list_statement)

    sources(:resource_list_rdf_class_source).property.update!(label: AddWebpagesJob::RDF_CLASS_LABEL)
    sources(:resource_list_uri_list_source).property.update!(label: AddWebpagesJob::URI_LIST_LABEL)
    sources(:resource_list_url_list_source).property.update!(label: AddWebpagesJob::WEBPAGE_URL_LIST_LABEL)
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
    assert_equal "RDF Class is blank", error.message

    @rdf_class_statement.destroy!
    error = assert_raises(AddWebpagesJob::InvalidResourceListError) do
      AddWebpagesJob.perform_now(@resource_list_page.url)
    end
    assert_equal "RDF Class is blank", error.message

    assert_equal 0, Webpage.where(url: ["https://example.org/events/1", "https://example.org/events/2"], website: @resource_list_page.website).count
    assert_equal 0, enqueued_jobs.count { |job| job[:job] == RefreshWebpageJob }
  end

  test "a legacy job for a data-only list succeeds without a uri list or new webpages" do
    @rdf_class_statement.update!(cache: "None")
    @uri_list_statement.destroy!

    assert_no_difference("Webpage.count") do
      assert_no_enqueued_jobs(only: RefreshWebpageJob) { AddWebpagesJob.perform_now(@resource_list_page.url) }
    end

    assert_equal '["https://example.org/events/1","https://example.org/events/2"]', @url_list_statement.reload.cache
  end

  test "a scheduled data-only list refresh stores its inputs and targets the right website when URLs are shared" do
    data_website = websites(:one)
    resource_list_class = RdfsClass.create!(name: "ResourceList")
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
end
