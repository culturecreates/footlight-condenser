module PreprocessingTestSupport
  def self.included(base)
    base.setup do
      @preprocessing_adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
    end
    base.teardown { ActiveJob::Base.queue_adapter = @preprocessing_adapter }
  end
  def build_preprocessing_fixture
    @website = Website.create!(seedurl: "preprocess-fixture-RList", name: "Preprocessing fixture", graph_name: "https://fixture.example/graph", default_language: "en")
    list_class = RdfsClass.find_or_create_by!(name: "ResourceList")
    derived_class = RdfsClass.find_or_create_by!(name: "WebPage")
    @list = Webpage.create!(website: @website, rdfs_class: list_class, url: "https://fixture.example/list", rdf_uri: "fixture:list", language: "en")
    @derived = Webpage.create!(website: @website, rdfs_class: derived_class, url: "https://fixture.example/derived", rdf_uri: "fixture:derived", language: "en")
    @property = Property.create!(label: "Mapping", value_datatype: "xsd:string", rdfs_class: derived_class)
    @source = Source.create!(website: @website, property: @property, language: "en", selected: true, algorithm_value: "ruby=['mapped value']")
    @input_source = Source.create!(website: @website, property: @property, language: "en", algorithm_value: "ruby=['input value']")
    @input = Statement.create!(source: @input_source, webpage: @list, cache: "input", status: "updated", cache_refreshed: Time.current, manual: false)
    @target = Statement.create!(source: @source, webpage: @derived, cache: "old value", status: "updated", cache_refreshed: 3.days.ago, manual: false)
    @policy = PreprocessingPolicy.create!(statement_id: @target.id, expected_seedurl: @website.seedurl, enabled: true,
      inputs_verified: true, input_statement_ids: [@input.id])
  end

  def queued_preprocessing_run
    Preprocessing::Dispatcher.dispatch(@policy)
  end
end
