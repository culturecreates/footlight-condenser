require "test_helper"
require "webmock/minitest"
require Rails.root.join("script/databus_replay")

class Distillator::DatabusReplayTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  include WebMock::API

  setup do
    @directory = Dir.mktmpdir("databus-replay")
    @base = "https://wringer.replay.test"
    @url = "https://example.org/event"
    @key = Distillator::WringerUrlKey.call(@url, include_fragment: true).uri_key
    @row = { "id" => 42, "uri" => @key, "http_response_code" => 200,
      "successful_refresh" => "2026-11-07T10:00:00Z", "updated_at" => "2026-11-07T10:00:00Z" }
  end

  teardown do
    FileUtils.remove_entry(@directory) if File.exist?(@directory)
    if @created_website
      Statement.where(webpage_id: @created_website.webpages.select(:id)).delete_all
      @created_website.sources.delete_all
      @created_website.webpages.delete_all
      @created_website.delete
      Property.where(id: @created_properties).delete_all
    end
  end

  test "cache misses do not call wring and unrelated search matches are rejected" do
    stub_request(:get, "#{@base}/websites.json").with(query: { term: @key }).to_return(json_response([@row.merge("uri" => "wrong")]))
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    assert_raises(Distillator::DatabusReplay::MissingInput) { reader.fetch(@url) }
    assert_not_requested :get, %r{/websites/wring}
  end

  test "cached body hydration sends no refresh rendering or POST flags and captures repeatable input" do
    stub_cache("<p>Théâtre</p>")
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    assert_equal "<p>Théâtre</p>", reader.fetch(@url)
    assert_equal "<p>Théâtre</p>", reader.fetch(@url)
    assert_requested :get, %r{\A#{Regexp.escape(@base)}/websites/wring.json\?}, times: 1 do |request|
      params = URI.decode_www_form(request.uri.query).to_h
      params.keys.sort == %w[include_fragment uri]
    end
    assert_equal "<p>Théâtre</p>".b, Base64.strict_decode64(reader.snapshot.first.fetch(:body_base64))
  end

  test "a cache version changed during hydration is incomplete rather than accepted" do
    stub_cache("<p>Changed</p>", after: @row.merge("updated_at" => "2026-11-15T10:00:00Z"))
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    error = assert_raises(Distillator::DatabusReplay::MissingInput) { reader.fetch(@url) }
    assert_match "cache changed", error.message
    assert_empty reader.observations
  end

  test "RDF comparison ignores blank node labels while retaining exact review timestamp differences" do
    service = build_service
    old = RDF::Graph.new << [RDF::Node.new("old"), RDF::Vocab::SCHEMA.name, "Event"]
    newer = RDF::Graph.new << [RDF::Node.new("new"), RDF::Vocab::SCHEMA.name, "Event"]
    assert service.send(:graph_difference, old, newer)[:exact_match]
    newer << [RDF::Node.new("new"), RDF::URI("http://schema.org/lastReviewed"), "2026-11-15"]
    diff = service.send(:graph_difference, old, newer)
    assert diff[:equivalent_event_data]
    assert_not diff[:exact_match]
    assert_empty diff[:data_added]
    newer << [RDF::Node.new("new"), RDF::Vocab::SCHEMA.startDate, "2026-12-18"]
    assert_not service.send(:graph_difference, old, newer)[:equivalent_event_data]
  end

  test "selected RDF scope includes EventSeries children and excludes unrelated events" do
    graph = RDF::Graph.new
    event, child, other, page = %w[event child other page].map { |id| RDF::URI("https://example.org/#{id}") }
    graph << [event, RDF.type, RDF::Vocab::SCHEMA.EventSeries]
    graph << [event, RDF::Vocab::SCHEMA.mainEntityOfPage, page]
    graph << [event, RDF::Vocab::SCHEMA.subEvent, child]
    graph << [child, RDF.type, RDF::Vocab::SCHEMA.Event]
    graph << [page, RDF::Vocab::SCHEMA.url, @url]
    graph << [other, RDF.type, RDF::Vocab::SCHEMA.Event]
    graph << [other, RDF::Vocab::SCHEMA.url, "https://example.org/unrelated"]
    service = build_service
    assert_equal [@url, "https://example.org/unrelated"], service.send(:event_source_urls, graph).sort
    sampled = service.send(:sampled_graph, graph, [@url])
    assert sampled.has_subject?(child)
    assert_not sampled.has_subject?(other)
  end

  test "raw extraction cannot fall back to a live HTTP call and the guard is restored after errors" do
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    stub_request(:get, "#{@base}/websites.json").with(query: { term: @key }).to_return(json_response([]))
    service = build_service(reader: reader)
    service.send(:install_guards)
    assert_raises(Distillator::DatabusReplay::MissingInput) do
      service.send(:with_cache_only) { HTTParty.get(@url) }
    end
    assert_not_requested :get, @url
    assert_nil Thread.current[:footlight_databus_replay]
    assert_nil Thread.current[:footlight_databus_transport]
  end

  test "Ruby HTTP JSON reads replay cache while request bodies and direct network access remain incomplete" do
    stub_cache('{"price":25}')
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    service = build_service(reader: reader)
    service.send(:install_guards)
    service.send(:with_cache_only) do
      response = HTTParty.get(@url)
      assert_equal 200, response.code
      assert_equal({ "price" => 25 }, response.parsed_response)
      assert_equal '{"price":25}', response.body
      assert_raises(Distillator::DatabusReplay::MissingInput) { HTTParty.post(@url, body: "not replayable") }
      assert_raises(Distillator::DatabusReplay::MissingInput) do
        Net::HTTP.start("uncaptured.example.org", 443, use_ssl: true) { |http| http.get("/") }
      end
    end
    assert_not_requested :get, @url
    assert_nil Thread.current[:footlight_databus_replay]
  end

  test "console replay regenerates selected source values and does not save statements or change website mode" do
    website, webpage = create_replay_records
    expected = [
      { "@id" => webpage.rdf_uri, "@type" => "http://schema.org/Event",
        "http://schema.org/name" => [{ "@value" => "Fresh title" }], "http://schema.org/url" => [{ "@value" => @url }] }
    ].to_json
    stub_cache("<h1>Fresh title</h1>")
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    counts = [Statement.count, Webpage.count, Website.count]
    report = build_service(reader: reader, export_loader: ->(_) { expected }).call
    assert_equal "equivalent_event_data", report[:sites].first[:status], report.inspect
    assert_equal 2, report[:sites].first[:source_executions]
    assert_equal counts, [Statement.count, Webpage.count, Website.count]
    assert_equal "Stored old title", Statement.find_by!(webpage: webpage).cache
    assert_equal "legacy", website.reload.distillator_mode
    assert File.exist?(File.join(@directory, "cache-inputs.json"))
    assert File.exist?(File.join(@directory, "co-motion-ca-selected-sources.json"))
  end

  test "binary tagged UTF8 Databus HTTP responses retain accented literals and exact downloaded bytes" do
    _website, webpage = create_replay_records
    title = "Théâtre — décembre à Montréal"
    export = [{ "@id" => webpage.rdf_uri, "@type" => "http://schema.org/Event",
      "http://schema.org/name" => [{ "@value" => title }], "http://schema.org/url" => [{ "@value" => @url }] }].to_json.b
    export_url = "https://data.culturecreates.com/databus/culture-creates/footlight/co-motion-ca/2026-11-07/co-motion-ca.json"
    stub_request(:get, export_url).to_return(status: 200, body: export, headers: { "Content-Type" => "application/octet-stream" })
    stub_cache("<h1>#{title}</h1>")
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    report = build_service(reader: reader).call
    assert_equal "equivalent_event_data", report[:sites].first[:status], report.inspect
    assert_equal export, File.binread(File.join(@directory, "co-motion-ca-production.json"))
    assert_equal Digest::SHA256.hexdigest(export), report[:sites].first[:export_sha256]
    assert_includes File.read(File.join(@directory, "co-motion-ca-actual.nq")), title
  end

  test "the replay transaction prevents accidental SQL writes" do
    create_replay_records
    service = build_service(export_loader: lambda { |_| Website.where(id: @created_website.id).update_all(name: "must not persist") })
    report = service.call
    assert_equal "incomplete", report[:sites].first[:status]
    assert_match "read-only", report[:sites].first[:error]
    assert_not_equal "must not persist", @created_website.reload.name
  end

  test "a failed site savepoint leaves the next site usable and mode is never changed" do
    create_replay_records
    service = Distillator::DatabusReplay.new(sites: %w[co-motion-ca culture3r-com], per_site: 1,
      output_dir: @directory, wringer_url: @base, progress: nil)
    website_id = @created_website.id
    service.define_singleton_method(:replay_site) do |seedurl|
      Website.where(id: website_id).update_all(distillator_mode: "active") if seedurl == "co-motion-ca"
      { seedurl: seedurl, status: "next_site_read_succeeded", website_count: Website.count }
    end
    report = service.call
    assert_equal "incomplete", report[:sites][0][:status]
    assert_equal "next_site_read_succeeded", report[:sites][1][:status]
    assert_equal "legacy", @created_website.reload.distillator_mode
  end

  test "console summary groups repeated missing input errors by URL" do
    report = { report_path: "report.json", sites: [{ seedurl: "co-motion-ca", pages: [{ url: @url,
      errors: [{ source_id: 1, error: "Missing cache" }, { source_id: 2, error: "Missing cache" }] }] }] }
    errors = Distillator::DatabusReplay.summary(report)[:sites].first[:input_or_extraction_errors]
    assert_equal 1, errors.count
    assert_equal 2, errors.first[:affected_sources]
    assert_equal [1, 2], errors.first[:source_ids]
  end

  private

  def json_response(value)
    { status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(value) }
  end

  def stub_cache(body, after: @row)
    stub_request(:get, "#{@base}/websites.json").with(query: { term: @key }).to_return(json_response([@row]))
    stub_request(:get, "#{@base}/websites/wring.json").with(query: { uri: @url, include_fragment: "true" }).to_return(json_response({ "html" => body }))
    stub_request(:get, "#{@base}/websites/42.json").to_return(json_response(after))
  end

  def build_service(**options)
    Distillator::DatabusReplay.new(sites: ["co-motion-ca"], per_site: 1, output_dir: @directory,
      wringer_url: @base, progress: nil, **options)
  end

  def create_replay_records
    # Avoid touching any pre-existing fixture site with the same seed.
    @created_website = Website.create!(name: "Databus replay fixture", seedurl: "co-motion-ca",
      graph_name: "https://example.org/replay", default_language: "en", distillator_mode: "legacy")
    event_class = RdfsClass.find_by!(name: "Event")
    webpage = Webpage.create!(website: @created_website, rdfs_class: event_class, url: @url,
      rdf_uri: "https://example.org/replay/event", language: "en")
    title = Property.create!(label: "Title", uri: "http://schema.org/name", value_datatype: "xsd:string", rdfs_class: event_class)
    link = Property.create!(label: "Webpage link", uri: "http://schema.org/url", value_datatype: "xsd:string", rdfs_class: event_class)
    @created_properties = [title.id, link.id]
    source = Source.create!(website: @created_website, property: title, selected: true, language: "", algorithm_value: "xpath=//h1")
    Source.create!(website: @created_website, property: link, selected: true, language: "", algorithm_value: "ruby=$url")
    Source.create!(website: @created_website, property: title, selected: false, language: "", algorithm_value: "ruby=raise 'unselected source executed'")
    Statement.create!(source: source, webpage: webpage, status: "ok", selected_individual: true, cache: "Stored old title")
    [@created_website, webpage]
  end
end
