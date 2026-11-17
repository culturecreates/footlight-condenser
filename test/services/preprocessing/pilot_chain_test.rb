require "test_helper"

class PreprocessingPilotChainTest < ActiveJob::TestCase
  include PreprocessingTestSupport
  setup { build_preprocessing_fixture }

  def eight_inputs
    @input.update!(cache: [{"id" => "event-0", "codes" => ["family"]}].to_json)
    [@input] + 7.times.map do |index|
      page = Webpage.create!(website: @website, rdfs_class: @list.rdfs_class, language: "en",
        url: "https://fixture.example/list-#{index}", rdf_uri: "fixture:list-#{index}")
      Statement.create!(webpage: page, source: @input_source, cache: [{"id" => "event-#{index + 1}", "codes" => ["adult"]}].to_json,
        status: "updated", manual: false, cache_refreshed: Time.current)
    end
  end

  test "eight lists two derived stages and an ordinary event refresh converge without ordering guarantees" do
    inputs = eight_inputs
    @source.update!(algorithm_value: "ruby=[Statement.where(id: #{inputs.map(&:id).inspect}).order(:id).flat_map { |s| JSON.parse(s.cache) }.to_json]")
    @target.update!(cache: "[]")
    @policy.update!(input_statement_ids: inputs.map(&:id))
    source = Source.create!(website: @website, property: @property, language: "en",
      algorithm_value: "ruby=[JSON.parse(Statement.find(#{@target.id}).cache).to_h { |row| [row.fetch('id'), row.fetch('codes')] }.to_json]")
    mapping = Statement.create!(webpage: @derived, source: source, cache: "{}", status: "updated", manual: false)
    policy = PreprocessingPolicy.create!(statement_id: mapping.id, expected_seedurl: @website.seedurl,
      enabled: true, inputs_verified: true, input_statement_ids: [@target.id])
    # Deliberately run downstream first. A later sweep catches up.
    run = Preprocessing::Dispatcher.dispatch(policy)
    Preprocessing::Runner.call(policy.id, run.id)
    assert_equal({}, JSON.parse(mapping.reload.cache))
    run = Preprocessing::Dispatcher.dispatch(@policy)
    Preprocessing::Runner.call(@policy.id, run.id)
    run = Preprocessing::Dispatcher.dispatch(policy, force: true)
    Preprocessing::Runner.call(policy.id, run.id)
    assert_equal 8, JSON.parse(mapping.reload.cache).size
    assert_equal ["family"], JSON.parse(mapping.cache).fetch("event-0")

    site = Website.create!(seedurl: "event-consumer", name: "Event consumer", graph_name: "https://events.example/graph", default_language: "en")
    page = Webpage.create!(website: site, rdfs_class: rdfs_classes(:one), language: "en", url: "https://events.example/event-0", rdf_uri: "fixture:event-0")
    property = Property.create!(rdfs_class: rdfs_classes(:one), label: "Audience", uri: "http://schema.org/audience", value_datatype: "xsd:string")
    source = Source.create!(website: site, property: property, language: "en", selected: true,
      algorithm_value: "ruby=JSON.parse(Statement.find(#{mapping.id}).cache).fetch('event-0')")
    errors = Distillator::RefreshRunner.call(webpage: page, refresh_helper: ApplicationController.helpers)
    assert_empty errors
    assert_equal "family", page.statements.find_by!(source: source).cache
  end

  test "eight category lists can feed one derived mapping with the unchanged DSL helper" do
    inputs = eight_inputs
    @policy.update!(input_statement_ids: inputs.map(&:id))
    @source.update!(algorithm_value: "ruby=[Statement.where(id: #{inputs.map(&:id).inspect}).order(:id).flat_map { |s| JSON.parse(s.cache) }.to_h { |row| [row.fetch('id'), row.fetch('codes')] }.to_json]")
    perform_enqueued_jobs(only: RefreshPreprocessingStatementJob) { Preprocessing::Dispatcher.call }
    assert_equal "succeeded", @policy.reload.last_result
    assert_equal 8, JSON.parse(@target.reload.cache).size
    assert_empty @policy.monitoring_issues
  end
end
