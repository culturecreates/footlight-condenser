require 'test_helper'

class ResourcesControllerTest < ActionDispatch::IntegrationTest
  # Uses fixtures: webpages(:one), rdfs_classes(:one), websites(:one)

  # === SHOW ===

  test "show returns resource with valid rdf_uri" do
    get show_resources_path(rdf_uri: webpages(:one).rdf_uri, format: :json)
    assert_response :success
    assert_match webpages(:one).rdf_uri, @response.body
  end

  # Don't test "missing path param"—Rails will raise before controller

  test "show returns 404 for non-existent rdf_uri" do
    get show_resources_path(rdf_uri: "does-not-exist", format: :json)
    assert_response :not_found
  end

  # === INDEX ===

  test "index returns resources for a valid website" do
    get website_all_resources_path(seedurl: websites(:one).seedurl, format: :json)
    assert_response :success
    assert_includes @response.body, "event"
    assert_includes @response.body, "place"
  end

  test "resources json index preserves grouped resource contract" do
    get website_all_resources_path(seedurl: websites(:one).seedurl, format: :json)

    assert_response :success
    payload = JSON.parse(@response.body)
    assert payload.is_a?(Hash)
    assert_includes payload.keys, "event"
    assert_includes payload.keys, "place"
  end

  test "resources index renders harmonized table shell and sortable headers" do
    assert_read_only_page_does_not_fetch
    get website_all_resources_path(seedurl: websites(:one).seedurl)

    assert_response :success
    assert_select ".harmonized-table-shell", 1
    assert_select 'th a[href*="sort=rdf_uri"]'
    assert_select 'th a[href*="sort=rdfs_class_name"]'
  end

  test "resources index falls back safely for invalid sort and direction" do
    get website_all_resources_path(seedurl: websites(:one).seedurl, sort: "bogus", direction: "sideways")

    assert_response :redirect
    assert_redirected_to website_all_resources_path(seedurl: websites(:one).seedurl)
  end

  test "resources nested canonical redirect does not duplicate seedurl query param" do
    get website_all_resources_path(seedurl: "one"), params: {
      sort: "bogus",
      direction: "sideways",
      seedurl: "one"
    }

    assert_response :redirect
    assert_redirected_to website_all_resources_path(seedurl: "one")
    assert_not_includes response.location, "?seedurl=one"
  end

  test "resources index renders empty state when website has no resources" do
    assert_read_only_page_does_not_fetch
    website = Website.create!(
      name: "empty resource website",
      seedurl: "empty-resource-website",
      graph_name: "http://example.com/empty-resource-website",
      default_language: "en",
      distillator_mode: "legacy"
    )

    get website_all_resources_path(seedurl: website.seedurl)

    assert_response :success
    assert_select ".harmonized-table-empty-state", 1
  end

  test "resources index does not fetch" do
    assert_read_only_page_does_not_fetch

    get website_all_resources_path(seedurl: websites(:one).seedurl)

    assert_response :success
  end

  test "index returns 404 if seedurl missing" do
    get "/websites//resources.json"
    assert_response :not_found
  end

  # === URI ===

  test "uri returns resource for valid uri param" do
    get uri_resources_path(uri: webpages(:one).rdf_uri)
    assert_response :success
    assert_match webpages(:one).rdf_uri, @response.body
  end

  test "resource uri page renders harmonized card hooks" do
    get uri_resources_path(uri: webpages(:one).rdf_uri)

    assert_response :success
    assert_select ".harmonized-card-grid", minimum: 1
    assert_select ".harmonized-card", minimum: 1
    assert_select ".harmonized-card-title", minimum: 1
    assert_select ".harmonized-card-value", minimum: 1
  end

  test "uri returns 400 if no param given" do
    get uri_resources_path
    assert_response :bad_request
    assert_includes @response.body, "Missing uri param"
  end

  # === RECON ===

  test "recon with valid query/type returns results" do
    get recon_resources_path(query: "Event", type: rdfs_classes(:one).name, format: :json)
    assert_response :success
    assert_includes @response.body, "result"
  end

  test "recon with missing params returns 400" do
    get recon_resources_path(format: :json)
    assert_response :bad_request
    assert_includes @response.body, "Missing required params"
  end

  # === CREATE RESOURCE ===

  # test "create_resource creates with valid params" do
    # post create_resource_path, params: {
      # rdfs_class: rdfs_classes(:one).name,           # "Event"
      # seedurl: websites(:one).seedurl,               # "one"
      # statements: { "Mystring" => [{ value: "Resource X", language: "en" }] }
    # }, as: :json
    # assert_response :created
    # assert_includes @response.body, "footlight:"
    # assert_includes @response.body, "Resource X"
  # end

  test "create_resource fails with missing rdfs_class" do
    post create_resource_path, params: { seedurl: websites(:one).seedurl, statements: { "name" => [{ value: "R", language: "en" }] } }, as: :json
    assert_response :unprocessable_entity
    assert_includes @response.body, "Missing one or more required params"
  end

  test "create_resource fails with no params" do
    post create_resource_path, params: {}, as: :json
    assert_response :unprocessable_entity
    assert_includes @response.body, "Missing one or more required params"
  end

  # === DESTROY ===

  test "destroy removes resource and redirects" do
    webpage = Webpage.create!(
      rdf_uri: "destroy-me", language: "en", url: "http://test",
      rdfs_class: rdfs_classes(:one), website: websites(:one)
    )
    assert_difference 'Webpage.count', -1 do
      delete destroy_resources_path(rdf_uri: webpage.rdf_uri)
      assert_response :redirect
    end
  end

  test "destroy for missing rdf_uri returns 404" do
    assert_no_difference 'Webpage.count' do
      delete destroy_resources_path(rdf_uri: "not-found")
      assert_response :not_found
    end
  end

  # === DELETE_URI ===

  test "delete_uri removes webpage via param and returns no content" do
    webpage = Webpage.create!(
      rdf_uri: "delete-this", language: "en", url: "http://test",
      rdfs_class: rdfs_classes(:one), website: websites(:one)
    )
    assert_difference 'Webpage.count', -1 do
      delete destroy_resource_uri_path, params: { uri: webpage.rdf_uri }, as: :json
      assert_response :no_content
    end
  end

  test "delete_uri with no matching page returns no content" do
    assert_no_difference 'Webpage.count' do
      delete destroy_resource_uri_path, params: { uri: "not-found" }, as: :json
      assert_response :no_content
    end
  end

  # === ARCHIVE ===

  # test "archive sets archive_date and redirects" do
    # webpage = Webpage.create!(
      # rdf_uri: "archive-me", language: "en", url: "http://test",
      # rdfs_class: rdfs_classes(:one), website: websites(:one)
    # )
    # patch archive_resources_path(rdf_uri: webpage.rdf_uri), params: { event: { status_origin: "archived" } }
    # assert_response :redirect
    # # Optionally: assert_not_nil webpage.reload.archive_date
  # end

  test "archive with non-existent rdf_uri returns 404" do
    patch archive_resources_path(rdf_uri: "does-not-exist"), params: { event: { status_origin: "archived" } }
    assert_response :not_found
  end

  # === REVIEWED_ALL ===

  # test "reviewed_all redirects for valid params" do
    # resource = Resource.create!(
      # rdf_uri: "reviewed-me", rdfs_class: rdfs_classes(:one), seedurl: websites(:one).seedurl
    # )
    # patch reviewed_all_resources_path(rdf_uri: resource.rdf_uri), params: { event: { status_origin: "reviewed" }, review_next: "false" }
    # assert_response :redirect
  # end

  test "reviewed_all with non-existent rdf_uri returns 404" do
    patch reviewed_all_resources_path(rdf_uri: "does-not-exist"), params: { event: { status_origin: "reviewed" } }
    assert_response :not_found
  end

  # === WEBPAGE_URLS ===

  test "webpage_urls returns JSON for valid rdf_uri" do
    get "/resources/#{webpages(:one).rdf_uri}/webpage_urls", as: :json
    assert_response :success
    assert_match webpages(:one).url, @response.body
  end

  test "webpage_urls with invalid rdf_uri returns 404" do
    get "/resources/unknown-uri/webpage_urls", as: :json
    assert_response :not_found
  end

  private

  def assert_read_only_page_does_not_fetch
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    Distillator::NativeFetch.expects(:call).never
    Distillator::FetchShadowComparator.expects(:call).never
  end
end
