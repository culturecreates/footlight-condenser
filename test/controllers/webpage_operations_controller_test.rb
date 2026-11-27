require "test_helper"

class WebpageOperationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @website = websites(:one)
    @website.update!(default_language: "en", distillator_mode: "active")
    @owner = websites(:two)
    @owner.update!(distillator_mode: "active")
    @resource_list = RdfsClass.find_or_create_by!(name: "ResourceList")
    @url_property = list_property(AddWebpagesJob::WEBPAGE_URL_LIST_LABEL)
    @uri_property = list_property(AddWebpagesJob::URI_LIST_LABEL)
    @class_property = list_property(AddWebpagesJob::RDF_CLASS_LABEL)
    @event_url = "https://example.org/current-event"
    @page = create_list
    Distillator::FetchGuard.stubs(:check_url).returns(Struct.new(:allowed?).new(true))
  end

  test "refetch, cached extraction, DSL failure and a failed fetch retain independent evidence" do
    html = list_html(@event_url)
    Distillator::FetchService.expects(:fetch_result).twice.with { |args| args[:scrape_options][:force_scrape] }
      .returns(fetch_result(html), fetch_failure)
    url_statement = @page.statements.joins(:source).find_by!(sources: { property_id: @url_property.id })
    stamp = url_statement.cache_refreshed

    post refetch_source_webpage_path(@page)
    assert_response :see_other
    assert_equal "Source refetched. Statement results were kept.", flash[:notice]
    assert_equal stamp, url_statement.reload.cache_refreshed
    refetched = operations[:fetch].fetch(:last_success_at)
    assert_equal :fresh, operations[:fetch][:state]

    post refresh_statements_webpage_path(@page)
    assert_response :see_other
    assert_match(/came from Condenser’s cache/, flash[:notice])
    proof = url_statement.reload.fetch_provenance.fetch("saved")
    primary = proof.fetch("primary")
    assert_equal Digest::SHA256.hexdigest(html), primary.fetch("fingerprint")
    assert_equal operations[:fetch][:cache_id], primary.fetch("cache_id")
    assert_equal refetched, Time.iso8601(primary.fetch("source_fetched_at"))
    assert_equal "cached", primary.fetch("usage")

    url_statement.source.update!(algorithm_value: "xpath=//no-such-element")
    post refresh_statements_webpage_path(@page)
    assert_match(/reported .*error/, flash[:alert])
    assert_equal proof, url_statement.reload.fetch_provenance.fetch("saved")
    assert_equal "failed", url_statement.fetch_provenance.dig("attempt", "result")
    assert_equal :inspect_extraction, diagnostics[:next_action]

    post refresh_statements_webpage_path(@page), params: { refetch: true }
    assert_match(/did not run/, flash[:alert])
    assert_equal :failed, operations[:fetch][:state]
    assert_equal refetched, operations[:fetch][:last_success_at]
    assert_equal 503, operations[:fetch][:http_status]
    assert_equal html, Distillator::FetchCache.find(operations[:fetch][:cache_id]).body
    assert_equal proof, url_statement.reload.fetch_provenance.fetch("saved")
  end

  test "a current statement refresh from old cached HTML leaves source freshness stale" do
    html = list_html(@event_url)
    Distillator::FetchService.expects(:fetch_result).once.returns(fetch_result(html))
    post refetch_source_webpage_path(@page)
    cache = Distillator::FetchCache.find(operations[:fetch][:cache_id])
    old_source = 49.hours.ago.floor(6)
    cache.update_columns(scrape_date: old_source, successful_refresh: old_source)

    post refresh_statements_webpage_path(@page)

    assert_match(/came from Condenser’s cache/, flash[:notice])
    evidence = diagnostics
    assert_equal :stale, evidence[:fetch][:state]
    assert_equal old_source, evidence[:fetch][:last_success_at]
    assert_operator evidence[:extraction][:last_success_at], :>, old_source
    assert_equal :refetch_source, evidence[:next_action]
  end

  test "combined action uses one refetch and records tracked secondary dependencies separately" do
    html = list_html(@event_url)
    Distillator::FetchService.expects(:fetch_result).once.returns(fetch_result(html))
    endpoint = "https://example.org/dependency?key=test-key"
    HTTParty.expects(:get).with(endpoint).returns(Struct.new(:code, :body).new(200, '["urn:item"]'))
    statement = @page.statements.joins(:source).find_by!(sources: { property_id: @uri_property.id })
    statement.source.update!(algorithm_value: "xpath=//a/@data-uri;api='#{endpoint}'")

    post refresh_statements_webpage_path(@page), params: { refetch: true }

    assert_response :see_other
    assert_match(/primary source was fetched/, flash[:notice])
    proof = statement.reload.fetch_provenance.fetch("saved")
    assert_equal "fetched", proof.dig("primary", "usage")
    dependency = proof.fetch("dependencies").sole
    assert_equal Digest::SHA256.hexdigest(endpoint), dependency.fetch("identity")
    assert_equal Digest::SHA256.hexdigest('["urn:item"]'), dependency.fetch("fingerprint")
    assert_equal 200, dependency.fetch("http_status")
    refute_includes proof.to_json, "test-key"
  end

  test "reconciliation creates only missing URLs, successfully does nothing on retry and leaves statements alone" do
    Distillator::FetchService.expects(:fetch_result).never
    assert_difference -> { @website.webpages.count }, 1 do
      post reconcile_urls_webpage_path(@page)
    end
    assert_match(/Imported 1 new webpage/, flash[:notice])
    assert_equal @event_url, @website.webpages.find_by!(url: @event_url).url
    assert_no_difference ["Webpage.count", "Statement.count"] do
      post reconcile_urls_webpage_path(@page)
    end
    assert_equal "Discovery complete. No new webpages to create.", flash[:notice]
    assert_equal :complete, diagnostics.dig(:reconciliation, :state)
    get websites_path
    assert_response :success
    assert_select "#website-details-#{@website.id} [data-readiness-reason=no_thorough_validation] a",
      text: "Run Thorough validation"
  end

  test "each linked list gets its own stale, invalid, or changed configuration reason" do
    other = create_list("stale")
    invalid = create_list("invalid", url: "mailto:events@example.org")
    @page.statements.joins(:source).find_by!(sources: { property_id: @url_property.id }).source.update!(algorithm_value: "xpath=//button")
    other.statements.where(manual: false).update_all(cache_refreshed: 3.days.ago)
    other.update_columns(created_at: 5.days.ago, updated_at: 5.days.ago)
    other.statements.where(manual: false).each do |statement|
      statement.source.update_column(:updated_at, 5.days.ago)
      statement.source.property.update_column(:updated_at, 5.days.ago)
    end

    assert_no_difference "Webpage.count" do
      post reconcile_urls_webpage_path(invalid)
    end
    lists = Distillator::WebsiteInventoryFreshness.for_websites([@website.id], diagnostics: true).fetch(@website.id).fetch(:lists)
      .index_by { |list| list[:webpage_id] }
    assert_equal :extraction_configuration_changed, lists.fetch(@page.id)[:reason]
    assert_equal :stale_list, lists.fetch(other.id).dig(:extraction, :reason)
    assert_equal :invalid_or_empty_list, lists.fetch(invalid.id)[:reason]
    assert_equal 1, lists.fetch(invalid.id).dig(:reconciliation, :invalid_urls)
    get webpage_path(invalid)
    assert_response :success
    assert_select "[data-resource-list-reason=invalid_or_empty_list]"
  end

  private

  def operations
    Distillator::WebpageOperationEvidence.for_pages([@page], discovery_only: true).fetch(@page.id)
  end

  def diagnostics
    Distillator::WebsiteInventoryFreshness.for_websites([@website.id], diagnostics: true).fetch(@website.id).fetch(:lists)
      .find { |list| list[:webpage_id] == @page.id }
  end

  def list_property(label)
    Property.create!(rdfs_class: @resource_list, label: label, value_datatype: "json", uri: "urn:#{label.parameterize}")
  end

  def create_list(suffix = "current", url: @event_url)
    owner = suffix == "current" ? @owner : Website.create!(seedurl: "discovery-#{suffix}", name: suffix, default_language: "en")
    page = owner.webpages.create!(url: "https://example.org/list/#{suffix}", language: "en",
      rdf_uri: "urn:list:#{suffix}", rdfs_class: @resource_list, discovery_target_website: @website)
    [
      [@class_property, "manual=Event", "Event"],
      [@url_property, "xpath=//a/@href;ruby=$array.to_json", [url].to_json],
      [@uri_property, "xpath=//a/@data-uri;ruby=$array.to_json", ["urn:item"].to_json]
    ].each do |property, algorithm, cache|
      source = owner.sources.create!(property: property, language: "en", algorithm_value: algorithm, selected: true)
      manual = property == @class_property
      statement = page.statements.create!(source: source, status: "ok", manual: manual, cache: cache,
        selected_individual: true, cache_refreshed: Time.current)
      statement.update_column(:status, "ok")
    end
    page
  end

  def list_html(url)
    %(<html><a href="#{url}" data-uri="urn:item">Event</a></html>)
  end

  def fetch_result(html)
    { status: :ok, body: html, raw_body: html, http_code: 200, fetch_path: "native",
      signals: { transport_success: true, content_success: true } }
  end

  def fetch_failure
    { status: :abort, body: ["abort_update", {}], raw_body: "", http_code: 503, fetch_path: "native",
      signals: { transport_success: false, content_success: false } }
  end
end
