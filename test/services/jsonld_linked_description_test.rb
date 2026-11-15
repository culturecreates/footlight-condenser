require "test_helper"

class JsonldLinkedDescriptionTest < ActiveSupport::TestCase
  setup do
    @schema = RDF::Vocabulary.new("http://schema.org/")
    @venue = RDF::URI("https://www.co-motion.ca/nos-salles-de-spectacles/salle-andre-mathieu/#Place")
    @category = RDF::URI("http://kg.footlight.io/resource/a9a70dca-dffc-430f-8afa-7b69674e5a1c")
    @event = RDF::URI("http://kg.footlight.io/resource/co-motion-ca_2freres-origine")
    @descriptions = RDF::Graph.load(Rails.root.join("test/fixtures/files/co_motion_linked_descriptions.nt").to_s, format: :ntriples)
    ArtsdataGraph.stubs(:graph).returns(@descriptions)
    JsonldGenerator.expects(:dereference_uri).never
  end

  test "the thirteen missing Co-motion triples match historical linked-resource enrichment" do
    assert_equal 13, @descriptions.count
    input = event_graph
    historical = event_graph
    [@venue, @category].each { |uri| historical << JsonldGenerator.describe_uri_old(uri) }
    actual = JsonldGenerator.add_triples_from_footlight(input)
    assert_equal 15, actual.count
    assert_equal historical.dump(:ntriples).lines.sort, actual.dump(:ntriples).lines.sort
    @descriptions.each_statement { |triple| assert actual.has_statement?(triple), triple.to_s }
  end

  test "category descriptions resolve both full and prefixed database identifiers using selected sources" do
    @descriptions.clear
    page = webpages(:seven)
    page.update!(rdf_uri: "footlight:a9a70dca-dffc-430f-8afa-7b69674e5a1c")
    statement = statements(:six)
    statement.update!(cache: "Musique")
    actual = JsonldGenerator.describe_uri(@category)
    assert actual.has_statement?(RDF::Statement.new(@category, @schema.name, RDF::Literal("Musique", language: :en)))

    page.update!(rdf_uri: @category.to_s)
    assert_equal actual.dump(:ntriples), JsonldGenerator.describe_uri(@category).dump(:ntriples)
    statement.source.update!(selected: false)
    assert_empty JsonldGenerator.describe_uri(@category)
  end

  test "a previous miss or description cannot stay cached across enrichment passes" do
    @descriptions.clear
    assert_equal 2, JsonldGenerator.add_triples_from_footlight(event_graph).count
    @descriptions << [@venue, @schema.name, "New venue"]
    assert JsonldGenerator.add_triples_from_footlight(event_graph).has_statement?(RDF::Statement.new(@venue, @schema.name, "New venue"))
    @descriptions.delete([@venue, @schema.name, "New venue"])
    @descriptions << [@venue, @schema.name, "Updated venue"]
    actual = JsonldGenerator.add_triples_from_footlight(event_graph)
    assert actual.has_statement?(RDF::Statement.new(@venue, @schema.name, "Updated venue"))
    assert_not actual.has_statement?(RDF::Statement.new(@venue, @schema.name, "New venue"))
  end

  test "enrichment retains a fixed root list and one nested level without pulling unrelated entities" do
    address = RDF::URI("#{@venue}-PostalAddress")
    deeper = RDF::URI("https://example.org/deeper")
    other_entity = RDF::URI("http://kg.artsdata.ca/resource/K11-unrelated")
    @descriptions << [address, @schema.url, deeper]
    @descriptions << [deeper, @schema.name, "Beyond one level"]
    @descriptions << [@venue, @schema.sameAs, other_entity]
    @descriptions << [other_entity, @schema.name, "Do not expand linked Artsdata entities"]
    @descriptions << [@schema.Place, @schema.name, "Do not describe vocabulary"]
    actual = JsonldGenerator.add_triples_from_footlight(event_graph)
    assert_equal 17, actual.count
    assert_not actual.has_subject?(deeper)
    assert_not actual.has_subject?(other_entity)
    assert_not actual.has_subject?(@schema.Place)
    assert_empty JsonldGenerator.describe_uri(RDF::URI("https://unknown.example.org/place"))
  end

  private

  def event_graph
    RDF::Graph.new.insert([@event, @schema.location, @venue], [@event, @schema.additionalType, @category])
  end
end
