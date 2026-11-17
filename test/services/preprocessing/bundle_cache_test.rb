require "test_helper"

class PreprocessingBundleCacheTest < ActiveJob::TestCase
  include PreprocessingTestSupport
  setup do
    build_preprocessing_fixture
    @policy.destroy!
    @list.destroy!
    @website.update!(seedurl: "co-motion-fixture", name: "Bundle fixture")
    @property.update!(label: "Bundle")
    @source.update!(selected: false, algorithm_value: %q{ruby=['{"offers":[{"price":53.0,"name":"Regular"}]}']})
    @policy = PreprocessingPolicy.create!(statement_id: @target.id, expected_seedurl: @website.seedurl,
      enabled: true, inputs_verified: true, input_statement_ids: [])
  end

  test "unselected Bundle is refreshed explicitly and Price can consume its saved JSON" do
    run = Preprocessing::Dispatcher.dispatch(@policy)
    Preprocessing::Runner.call(@policy.id, run.id)
    assert_equal "succeeded", run.reload.status
    assert_equal 53.0, JSON.parse(@target.reload.cache).fetch("offers").first.fetch("price")
    assert_not @source.reload.selected
    property = Property.create!(label: "Price", value_datatype: "xsd:float", rdfs_class: @derived.rdfs_class, uri: "http://schema.org/price")
    source = Source.create!(website: @website, property: property, language: "en",
      algorithm_value: "ruby=JSON.parse(Statement.find(#{@target.id}).cache).fetch('offers').map { |offer| offer.fetch('price') }")
    statement = Statement.create!(webpage: @derived, source: source, cache: "old", status: "updated", manual: false)
    policy = PreprocessingPolicy.create!(statement_id: statement.id, expected_seedurl: @website.seedurl, enabled: true,
      inputs_verified: true, input_statement_ids: [@target.id])
    run = Preprocessing::Dispatcher.dispatch(policy)
    Preprocessing::Runner.call(policy.id, run.id)
    assert_equal "succeeded", run.reload.status
    assert_equal "53.0", statement.reload.cache
    description_property = Property.create!(label: "Price description", value_datatype: "xsd:string", rdfs_class: @derived.rdfs_class)
    description_source = Source.create!(website: @website, property: description_property, language: "en",
      algorithm_value: "ruby=JSON.parse(Statement.find(#{@target.id}).cache).fetch('offers').map { |offer| offer.fetch('name') }")
    description = Statement.create!(webpage: @derived, source: description_source, cache: "old description", status: "updated", manual: false)
    description_policy = PreprocessingPolicy.create!(statement_id: description.id, expected_seedurl: @website.seedurl,
      enabled: true, inputs_verified: true, input_statement_ids: [@target.id])
    description_run = Preprocessing::Dispatcher.dispatch(description_policy)
    Preprocessing::Runner.call(description_policy.id, description_run.id)
    assert_equal "succeeded", description_run.reload.status
    assert_equal "Regular", description.reload.cache
    assert_empty @policy.monitoring_issues
  end

  test "Bundle failure preserves its last good payload and reports the failure" do
    @target.update!(cache: '{"offers":[{"price":53.0}]}')
    @source.update!(algorithm_value: "ruby=['abort_update',{error:'Ticket service unavailable'}]")
    run = Preprocessing::Dispatcher.dispatch(@policy)
    Preprocessing::Runner.call(@policy.id, run.id)
    assert_equal "failed", run.reload.status
    assert_equal 53.0, JSON.parse(@target.reload.cache).fetch("offers").first.fetch("price")
    assert @policy.monitoring_issues.exists?(kind: "preprocessing_failure")
  end
end
