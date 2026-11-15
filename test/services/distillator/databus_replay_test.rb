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
    @key = Distillator::WringerUrlKey.legacy(@url, include_fragment: true).uri_key
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

  test "Culture Mauricie API mapping replays an explicit snapshot and retains missing category keys" do
    api = "https://footlight-condenser.herokuapp.com/statements.json?prop=121&seedurl=culturemauricie_lepointdevente-com-RList"
    body = [{ cache: { url_to_categories: { "65g261128001" => ["1"], "8uj270228001" => ["11"] } }.to_json }].to_json
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base, api_inputs: {
      api => { body: body, captured_at: "2026-11-15T12:00:00Z", provenance: "Production Condenser RList response" }
    })
    service = build_service(reader: reader)
    service.send(:install_guards)
    algorithm = <<~RUBY
      api="#{api}"
      ;ruby=JSON.parse($array.first['cache'])
      ;ruby=
      category_mapping = {"1" => "Musique", "3" => "Théâtre", "4" => "Danse", "5" => "Arts Visuels", "6" => "Arts littéraires", "11" => "Humour"}
      result = ''
      url_key=$url.gsub(/\\?lang=fr/,'').gsub(/.*\\/billets\\//,'')
      if $array['url_to_categories'].key?(url_key)
        result = $array['url_to_categories'][url_key].map { |id| category_mapping[id] }
      else
        result = "Key '\#{url_key}' not found in any category"
      end
      result
    RUBY
    { "65g261128001" => ["Musique"], "8uj270228001" => ["Humour"],
      "06n261114001" => "Key '06n261114001' not found in any category" }.each do |key, expected|
      runner = Distillator::DatabusReplay::CacheRunner.new(
        { url: "https://lepointdevente.com/billets/#{key}?lang=fr", render_js: false, scrape_options: {},
          tracer: Dsl::Tracing::NullTracer.new }, reader: reader)
      assert_equal expected, service.send(:with_cache_only) { runner.run(algorithm) }
    end
    assert_empty reader.missing
    evidence = reader.snapshot.sole
    assert_equal "supplied_api_snapshot", evidence[:source]
    assert_equal "2026-11-15T12:00:00Z", evidence[:captured_at]
    assert_equal "Production Condenser RList response", evidence[:provenance]
    assert_equal Digest::SHA256.hexdigest(body), evidence[:sha256]
    assert_equal body.b, Base64.strict_decode64(evidence[:body_base64])
    assert_not_requested :get, api
    assert_not_requested :get, %r{\A#{Regexp.escape(@base)}/}

    # A snapshot for this exact API must not become a general live fallback.
    changed_api = api.sub("prop=121", "prop=122")
    key = Distillator::WringerUrlKey.legacy(changed_api, include_fragment: true).uri_key
    stub_request(:get, "#{@base}/websites.json").with(query: { term: key }).to_return(json_response([]))
    assert_raises(Distillator::DatabusReplay::MissingInput) do
      service.send(:with_cache_only) { HTTParty.get(changed_api) }
    end
    assert_not_requested :get, changed_api
  end

  test "API snapshots require valid JSON capture time and provenance before replay starts" do
    input = { body: '{"value":1}', captured_at: "2026-11-15T12:00:00Z", provenance: "Captured response" }
    [{ body: "<html>not JSON</html>" }, { captured_at: "unknown" }, { provenance: "" }].each do |invalid|
      assert_raises(ArgumentError, JSON::ParserError) do
        Distillator::DatabusReplay::CacheReader.new(base_url: @base, api_inputs: { @url => input.merge(invalid) })
      end
    end
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    assert_raises(ArgumentError) { build_service(reader: reader, api_inputs: { @url => input }) }
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

  test "Culture3R secondary ticket requests preserve the exact existing Wringer query key" do
    @url = "https://billets.culture3r.com/Online/mapSelect.asp?doWork::WSmap::loadMap=Load&createBO::WSmap=1" \
      "&BOparam::WSmap::loadMap::performance_ids=4654FB70-AE58-44D8-B264-6E44B1BB9FC6&label=a%20b&label=a+b"
    @key = Distillator::WringerUrlKey.legacy(@url, include_fragment: true).uri_key
    @row = @row.merge("uri" => @key)
    stub_cache('{"price":53}')
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    service = build_service(reader: reader)
    service.send(:install_guards)
    service.send(:with_cache_only) do
      assert_equal({ "price" => 53 }, HTTParty.get(@url).parsed_response)
    end
    assert_equal @url, reader.observations.sole.fetch(:url)
    assert_empty reader.missing
    assert_not_requested :get, %r{\Ahttps://billets\.culture3r\.com/}
    assert_nil Thread.current[:footlight_databus_replay]
  end

  test "secondary query options are appended without rewriting the existing query" do
    url = "https://billets.culture3r.com/Online/mapSelect.asp?doWork::WSmap::loadMap=Load&label=a%20b&label=a+b"
    @url = "#{url}&lang=fr"
    @key = Distillator::WringerUrlKey.legacy(@url, include_fragment: true).uri_key
    @row = @row.merge("uri" => @key)
    stub_cache('{"price":53}')
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    [{ lang: "fr" }, "lang=fr"].each do |query|
      assert_equal({ "price" => 53 }, reader.http_response(url, query: query).parsed_response)
    end
    assert_equal @url, reader.observations.sole.fetch(:url)
    assert_empty reader.missing
    assert_not_requested :get, %r{\Ahttps://billets\.culture3r\.com/}
  end

  test "already encoded secondary URLs retain their original escape spelling" do
    @url = "https://billets.culture3r.com/Online/mapSelect.asp?doWork%3a%3aWSmap%3a%3aloadMap=Load&path=a%2fb&label=a%20b"
    @key = Distillator::WringerUrlKey.legacy(@url, include_fragment: true).uri_key
    @row = @row.merge("uri" => @key)
    stub_cache('{"price":53}')
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    assert_equal({ "price" => 53 }, reader.http_response(@url, {}).parsed_response)
    assert_equal @url, reader.observations.sole.fetch(:url)
    assert_empty reader.missing
  end

  test "source 5832 renderjs navigation finds the existing decoded Culture3R ticket cache" do
    main = "https://www.culture3r.com/evenements/18_p_r_a_c_t_i_c_e_s/"
    ticket = "https://billets.culture3r.com/Online/mapSelect.asp?doWork%3A%3AWSmap%3A%3AloadMap=Load&createBO%3A%3AWSmap=1" \
      "&BOparam%3A%3AWSmap%3A%3AloadMap%3A%3Aperformance_ids=4654FB70-AE58-44D8-B264-6E44B1BB9FC6"
    main_key = Distillator::WringerUrlKey.legacy(main, include_fragment: true).uri_key
    ticket_key = Distillator::WringerUrlKey.legacy(ticket, include_fragment: true).uri_key
    main_row = @row.merge("id" => 41, "uri" => main_key)
    ticket_row = @row.merge("id" => 113047, "uri" => ticket_key)
    stub_cache('<div class="c-event-details__tickets"><a class="o-button" href="' + ticket.gsub('&', '&amp;') + '">Billets</a></div>',
      url: main, key: main_key, row: main_row)
    ticket_body = '<div class="tuxCmsEdit__webEventSelection--category"><span>Catégories</span><span>Danse</span><span>Performance</span></div>'
    stub_cache(ticket_body, url: ticket, key: ticket_key, row: ticket_row)
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    runner = Distillator::DatabusReplay::CacheRunner.new(
      { url: main, render_js: false, scrape_options: {}, tracer: Dsl::Tracing::NullTracer.new }, reader: reader)
    Distillator::FetchCacheStore.expects(:fetch).never
    Distillator::FetchService.expects(:fetch).never
    algorithm = <<~'DSL'
      ruby=$array << "C3R NoEventTypeFound"
      ;if_xpath=//div[@class='c-event-details__tickets']//a[contains(@class,'o-button')]/@href
      ;renderjs_url=$array.uniq.second.gsub(/\/202.*/,'')
      ;ruby=$array.clear()
      ;xpath=//div[@class='tuxCmsEdit__webEventSelection--category']/span
      ;ruby=$array.size > 1 ? $array.drop(1).map{|e| e.squish} : $array
    DSL
    assert_equal ["Danse", "Performance"], runner.run(algorithm)
    observation = reader.observations.find { |entry| entry[:cache_id] == 113047 }
    assert_equal ticket, observation[:url]
    assert_equal CGI.unescape(ticket), observation[:canonical_url]
    assert_equal ticket_key, observation[:cache_uri_key]
    assert_equal ticket_body.b, Base64.strict_decode64(reader.snapshot.find { |entry| entry[:cache_id] == 113047 }[:body_base64])
    assert_empty reader.missing
    assert_not_requested :get, %r{\Ahttps://billets\.culture3r\.com/}
  end

  test "legacy key normalization does not double decode the URL sent for cache hydration" do
    @url = "https://example.org/event?value=a%2526b%2Bc"
    @key = Distillator::WringerUrlKey.legacy(@url, include_fragment: true).uri_key
    @row = @row.merge("uri" => @key)
    stub_cache("<h1>Known cached response</h1>")
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    assert_equal "<h1>Known cached response</h1>", reader.fetch(@url)
    assert_equal "https://example.org/event?value=a%26b+c", reader.observations.sole[:canonical_url]
    assert_requested :get, "#{@base}/websites/wring.json", query: { uri: @url, include_fragment: "true" }
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

  test "report identifies used API snapshots separately from Wringer HTML and preserves both bodies" do
    _website, webpage = create_replay_records
    source = @created_website.sources.find_by!(selected: true, property_id: @created_properties.first)
    api = "https://condenser.replay.test/statements.json?prop=121"
    source.update!(algorithm_value: "api=\"#{api}\";ruby=$array.fetch('title')")
    @created_website.sources.find_by!(property_id: @created_properties.last).update!(algorithm_value: "xpath=//h1;ruby=$url")
    body = '{"title":"Supplied API title"}'
    input = { body: body, captured_at: "2026-11-15T12:00:00Z", provenance: "Current production API observation" }
    expected = [{ "@id" => webpage.rdf_uri, "@type" => "http://schema.org/Event",
      "http://schema.org/name" => [{ "@value" => "Supplied API title" }], "http://schema.org/url" => [{ "@value" => @url }] }].to_json
    stub_cache("<h1>Wringer HTML still used for XPath extraction</h1>")
    report = build_service(api_inputs: { api => input }, export_loader: ->(_) { expected }).call
    assert_equal "equivalent_event_data", report[:sites].first[:status], report.inspect
    assert_equal "remote_wringer_cache", report[:input_backend]
    assert_equal api, report[:api_inputs].sole[:url]
    assert_equal input[:provenance], report[:api_inputs].sole[:provenance]
    assert_equal report[:api_inputs], Distillator::DatabusReplay.summary(report)[:api_inputs]
    recorded = JSON.parse(File.read(File.join(@directory, "cache-inputs.json")))
    assert_equal 2, recorded.count
    snapshot = recorded.find { |entry| entry["source"] == "supplied_api_snapshot" }
    assert_equal body.b, Base64.strict_decode64(snapshot.fetch("body_base64"))
    assert recorded.any? { |entry| entry["cache_id"] == @row["id"] }
    assert_not_requested :get, api
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

  test "Shadow replay uses only Wringer cache and preserves the existing Shadow mode" do
    website, webpage = create_replay_records(mode: "shadow")
    expected = [{ "@id" => webpage.rdf_uri, "@type" => "http://schema.org/Event",
      "http://schema.org/name" => [{ "@value" => "Fresh title" }], "http://schema.org/url" => [{ "@value" => @url }] }].to_json
    stub_cache("<h1>Fresh title</h1>")
    Distillator::FetchService.expects(:fetch).never
    Distillator::FetchCacheStore.expects(:fetch).never
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: @base)
    report = build_service(reader: reader, export_loader: ->(_) { expected }).call
    assert_equal "equivalent_event_data", report[:sites].first[:status], report.inspect
    assert_equal "shadow", report[:sites].first[:rollout_mode]
    assert_equal "shadow", website.reload.distillator_mode
    assert_equal "remote_wringer_cache", report[:input_backend]
    assert_equal @base, report[:wringer_url]
  end

  test "default Wringer identity is independent of Condenser compatibility configuration" do
    Distillator::WringerEndpoint.expects(:current).never
    service = Distillator::DatabusReplay.new(output_dir: @directory, progress: nil)
    assert_equal "https://footlight-wringer.herokuapp.com", service.instance_variable_get(:@reader).source_url
    reader = Distillator::DatabusReplay::CacheReader.new(base_url: "https://user:password@wringer.replay.test")
    assert_equal "https://wringer.replay.test", reader.source_url
  end

  test "Active sites are reported before fetching inputs and retain their mode" do
    website, = create_replay_records(mode: "active")
    loader = mock("export loader")
    loader.expects(:call).never
    report = build_service(export_loader: loader).call
    assert_equal "incomplete", report[:sites].first[:status]
    assert_match "Legacy or Shadow", report[:sites].first[:error]
    assert_equal "active", website.reload.distillator_mode
    assert_empty report[:cache_inputs]
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

  test "EventSeries failure identifies its page and keeps other events as an incomplete preview" do
    website, webpage = create_replay_records
    healthy = Webpage.new(website: website, rdfs_class: webpage.rdfs_class, language: "en",
      rdf_uri: "https://example.org/replay/healthy", url: "https://example.org/healthy")
    pages = [webpage, healthy].map do |page|
      bad = page == webpage
      dates = (bad ? 6 : 1).times.map { |index| "2026-12-#{index + 10}T20:00:00-05:00" }
      locations = ["Extracted venue", "Place"] + (bad ? 15 : 1).times.map do |index|
        ["Candidate #{index}", "https://example.org/venue/#{index}"]
      end
      values = [[properties(:ten), dates.to_json], [properties(:seven), locations.to_json]]
      statements = values.map do |property, cache|
        source = Source.new(website: website, property: property, language: "", selected: true, algorithm_value: "ruby=[]")
        Statement.new(source: source, webpage: page, cache: cache, status: "updated", selected_individual: true)
      end
      { url: page.url, statements: statements, sources: [], errors: [] }
    end
    baseline = [webpage, healthy].map do |page|
      { "@id" => page.rdf_uri, "@type" => "http://schema.org/Event", "http://schema.org/url" => [{ "@value" => page.url }] }
    end.to_json
    service = build_service(per_site: 2, export_loader: ->(_) { baseline })
    pages.each { |page| service.stubs(:extract_page).with(website, page[:url]).returns(page) }
    report = service.call
    site = report[:sites].sole
    assert_equal "incomplete", site[:status], site.inspect
    assert site[:pages], site.inspect
    error = site[:pages].find { |page| page[:url] == webpage.url }[:errors].sole
    assert_equal "export", error[:layer]
    assert_equal webpage.rdf_uri, error[:rdf_uri]
    assert_equal [6, 0, 15], error.values_at(:start_dates, :end_dates, :locations)
    assert_empty site[:pages].find { |page| page[:url] == healthy.url }[:errors]
    actual = File.read(File.join(@directory, "co-motion-ca-actual.nq"))
    assert_includes actual, healthy.rdf_uri
    summary_error = Distillator::DatabusReplay.summary(report)[:sites].sole[:input_or_extraction_errors].sole
    assert_equal webpage.url, summary_error[:url]
    assert_equal "export", summary_error[:layer]
    assert_equal 15, summary_error[:locations]
    assert_equal 0, summary_error[:affected_sources]
    recorded = JSON.parse(File.read(File.join(@directory, "co-motion-ca-extraction.json")))
    assert_equal "export", recorded.find { |page| page["url"] == webpage.url }["errors"].sole["layer"]
  end

  private

  def json_response(value)
    { status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(value) }
  end

  def stub_cache(body, url: @url, key: @key, row: @row, after: nil)
    stub_request(:get, "#{@base}/websites.json").with(query: { term: key }).to_return(json_response([row]))
    stub_request(:get, "#{@base}/websites/wring.json").with(query: { uri: url, include_fragment: "true" }).to_return(json_response({ "html" => body }))
    stub_request(:get, "#{@base}/websites/#{row.fetch('id')}.json").to_return(json_response(after || row))
  end

  def build_service(**options)
    Distillator::DatabusReplay.new(sites: ["co-motion-ca"], per_site: 1, output_dir: @directory,
      wringer_url: @base, progress: nil, **options)
  end

  def create_replay_records(mode: "legacy")
    # Avoid touching any pre-existing fixture site with the same seed.
    @created_website = Website.create!(name: "Databus replay fixture", seedurl: "co-motion-ca",
      graph_name: "https://example.org/replay", default_language: "en", distillator_mode: mode)
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
