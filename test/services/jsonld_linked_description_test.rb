require "test_helper"

class JsonldLinkedDescriptionTest < ActiveSupport::TestCase
  setup do
    @schema = RDF::Vocabulary.new("http://schema.org/")
    @venue = RDF::URI("https://www.co-motion.ca/nos-salles-de-spectacles/salle-andre-mathieu/#Place")
    @category = RDF::URI("http://kg.footlight.io/resource/a9a70dca-dffc-430f-8afa-7b69674e5a1c")
    @event = RDF::URI("http://kg.footlight.io/resource/co-motion-ca_2freres-origine")
    @descriptions = RDF::Graph.load(Rails.root.join("test/fixtures/files/co_motion_linked_descriptions.nt").to_s, format: :ntriples)
    @venue_page = resource_page(@venue, "Place")
    @category_page = resource_page("footlight:a9a70dca-dffc-430f-8afa-7b69674e5a1c", "EventType")
    local_statement(@venue_page, @schema.name, "Salle André-Mathieu", language: "fr")
    local_statement(@venue_page, @schema.sameAs, "http://kg.artsdata.ca/resource/K11-211", uri: true)
    { "addressCountry" => ["CA", "fr"], "addressLocality" => ["Laval", "fr"], "addressRegion" => ["Québec", "fr"],
      "postalCode" => [" H7N 5H9", nil], "streetAddress" => ["475 Bd de l'Avenir", "fr"] }.each do |predicate, (value, language)|
      local_statement(@venue_page, @schema[predicate], value, language: language, property_class: "PostalAddress")
    end
    local_statement(@category_page, RDF::URI("http://www.w3.org/2004/02/skos/core#prefLabel"), "Musique", language: "fr")
    local_statement(@category_page, RDF::URI("http://www.w3.org/2004/02/skos/core#closeMatch"),
      "http://kg.artsdata.ca/resource/MusicPerformance", uri: true)
    JsonldGenerator.expects(:dereference_uri).never
    LocalGraphGenerator.expects(:graph_all).never
  end

  test "the thirteen missing Co-motion triples match historical enrichment without loading remote graphs" do
    assert_equal 13, @descriptions.count
    historical = event_graph
    ArtsdataGraph.stubs(:graph).returns(@descriptions)
    [@venue, @category].each { |uri| historical << JsonldGenerator.describe_uri_old(uri) }
    ArtsdataGraph.unstub(:graph)
    expect_database_only

    actual = JsonldGenerator.add_triples_from_footlight(event_graph)
    assert_equal 15, actual.count
    assert_equal historical.dump(:ntriples).lines.sort, actual.dump(:ntriples).lines.sort
    @descriptions.each_statement { |triple| assert actual.has_statement?(triple), triple.to_s }
  end

  test "category descriptions resolve full and prefixed database identifiers using selected sources" do
    expect_database_only
    actual = JsonldGenerator.describe_footlight_uri(@category)
    assert_equal 3, actual.count
    @category_page.update!(rdf_uri: @category.to_s)
    assert_equal actual.dump(:ntriples).lines.sort, JsonldGenerator.describe_footlight_uri(@category).dump(:ntriples).lines.sort
    Source.where(id: @category_page.statements.select(:source_id)).update_all(selected: false)
    assert_empty JsonldGenerator.describe_footlight_uri(@category)
  end

  test "a previous miss or description cannot stay cached across enrichment passes" do
    expect_database_only
    Statement.where(webpage_id: [@venue_page.id, @category_page.id]).delete_all
    assert_equal 2, JsonldGenerator.add_triples_from_footlight(event_graph).count
    statement = local_statement(@venue_page, @schema.name, "New venue")
    assert JsonldGenerator.add_triples_from_footlight(event_graph).has_statement?(RDF::Statement.new(@venue, @schema.name, "New venue"))
    statement.update!(cache: "Updated venue")
    actual = JsonldGenerator.add_triples_from_footlight(event_graph)
    assert actual.has_statement?(RDF::Statement.new(@venue, @schema.name, "Updated venue"))
    assert_not actual.has_statement?(RDF::Statement.new(@venue, @schema.name, "New venue"))
  end

  test "enrichment does not follow new links or include unrelated event and Artsdata resources" do
    expect_database_only
    deeper = RDF::URI("https://example.org/deeper")
    other_entity = RDF::URI("http://kg.artsdata.ca/resource/K11-unrelated")
    deeper_page = resource_page(deeper, "Place")
    local_statement(deeper_page, @schema.name, "Do not recursively expand this place")
    local_statement(@venue_page, @schema.url, deeper.to_s, uri: true)
    local_statement(@venue_page, @schema.parentOrganization, other_entity.to_s, uri: true)
    event_page = resource_page("http://kg.footlight.io/resource/other-event", "Event")
    local_statement(event_page, @schema.name, "Do not describe other events")
    input = event_graph << [@event, @schema.subEvent, RDF::URI(event_page.rdf_uri)]
    actual = JsonldGenerator.add_triples_from_footlight(input)
    assert_equal 18, actual.count
    assert_not actual.has_subject?(deeper)
    assert_not actual.has_subject?(other_entity)
    assert_not actual.has_subject?(RDF::URI(event_page.rdf_uri))
    assert_not actual.has_subject?(@schema.Place)
    assert_empty JsonldGenerator.describe_footlight_uri(RDF::URI("https://unknown.example.org/place"))
  end

  private

  def expect_database_only
    ArtsdataGraph.expects(:graph).never
    RDF::Graph.expects(:load).never
  end

  def resource_page(uri, name)
    Webpage.create!(website: websites(:one), rdfs_class: RdfsClass.find_or_create_by!(name: name),
      url: uri.to_s, rdf_uri: uri.to_s, language: "fr")
  end

  def local_statement(page, predicate, value, language: nil, uri: false, property_class: nil)
    property = Property.create!(label: predicate.to_s.split(%r{[/#]}).last, uri: predicate.to_s,
      value_datatype: uri ? "xsd:anyURI" : "MyString", rdfs_class: property_class ? RdfsClass.find_or_create_by!(name: property_class) : page.rdfs_class)
    source = Source.create!(website: page.website, property: property, selected: true, language: language,
      algorithm_value: "manual=fixture", render_js: false)
    cache = uri ? [value, page.rdfs_class.name, [value, value]].to_json : value
    Statement.create!(webpage: page, source: source, cache: cache, status: "ok", selected_individual: true)
  end

  def event_graph
    RDF::Graph.new.insert([@event, @schema.location, @venue], [@event, @schema.additionalType, @category])
  end
end
