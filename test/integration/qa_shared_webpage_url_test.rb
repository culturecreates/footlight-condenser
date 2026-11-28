require "test_helper"

class QaSharedWebpageUrlTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @original = Website.create!(name: "Danse Danse", seedurl: "dansedanse-ca",
      graph_name: "https://example.org/dansedanse", default_language: "fr")
    @copy = Website.create!(name: "Danse Danse QA", seedurl: "dansedansetest-ca",
      graph_name: "https://example.org/dansedanse", default_language: "fr",
      test_copy_of_website: @original)
    @url = "https://www.dansedanse.ca/fr/spectacles/qa-pair"
    cls = RdfsClass.find_or_create_by!(name: "Event")
    @original_page = Webpage.create!(url: @url, website: @original, language: "fr",
      rdf_uri: "rdf:dansedanse-ca:qa-pair", rdfs_class: cls)
    @copied_page = Webpage.create!(url: @url, website: @copy, language: "fr",
      rdf_uri: "rdf:dansedansetest-ca:qa-pair", rdfs_class: cls)
  end

  test "public URL-only JSON-LD resolution ignores QA copy and scoped resolution can inspect it" do
    JsonldGenerator.expects(:dump_events).with([@original_page.rdf_uri]).returns("[]")
    get graphs_webpage_event_artsdasta_path(url: @url)
    assert_response :success

    JsonldGenerator.expects(:dump_events).with([@copied_page.rdf_uri]).returns("[]")
    get graphs_webpage_event_artsdasta_path(url: @url, website_id: @copy.id)
    assert_response :success
  end

  test "legacy URL-only statement refresh fails closed with a copy" do
    patch refresh_webpage_statements_path(url: @url)
    assert_response :conflict
    assert_equal 2, Webpage.where(url: @url).count
  end

  test "non-QA duplicate source URL is explicitly ambiguous in public JSON-LD" do
    another = Website.create!(name: "Other production", seedurl: "other-prod-ca",
      graph_name: "https://example.org/other-prod", default_language: "fr")
    Webpage.create!(url: @url, website: another, language: "fr",
      rdf_uri: "rdf:other-prod-ca:qa-pair", rdfs_class: @original_page.rdfs_class)

    JsonldGenerator.expects(:dump_events).never
    get graphs_webpage_event_artsdasta_path(url: @url)
    assert_response :conflict
  end
end
