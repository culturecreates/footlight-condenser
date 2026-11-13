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

  test "missing rdf class creates none and raises" do
    @rdf_class_statement.update!(cache: "")

    assert_raises(AddWebpagesJob::InvalidResourceListError) do
      AddWebpagesJob.perform_now(@resource_list_page.url)
    end

    assert_equal 0, Webpage.where(url: ["https://example.org/events/1", "https://example.org/events/2"], website: @resource_list_page.website).count
    assert_equal 0, enqueued_jobs.count { |job| job[:job] == RefreshWebpageJob }
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
