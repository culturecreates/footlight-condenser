require "json"
require "digest"
require "fileutils"
require "base64"
require "net/http"
require "time"
require "rdf/normalize"

module Distillator
  # Read-only, console-driven comparison of regenerated selected-source values
  # against a dated production export. This is not a rollout/activation check.
  class DatabusReplay
    # Kept for explicit reruns of the original pilot.
    HISTORICAL_EXPORTS = {
      "co-motion-ca" => "2026-11-07", "culture3r-com" => "2026-11-07", "placedesarts-com" => "2026-11-07",
      "culturemauricie_lepointdevente-com" => "2026-11-07", "gatineau-cloud" => "2026-11-07",
      "maisondelaculture-ca" => "2026-11-07", "tourismedeschenaux-ca" => "2026-11-08"
    }.freeze
    SCHEMA = "http://schema.org/".freeze
    DEFAULT_WRINGER_URL = "https://footlight-wringer.herokuapp.com".freeze
    class MissingInput < StandardError; end

    # These guards are inert outside this thread's extraction phase. A DSL must
    # not silently issue a fresh ticketing/API request while replaying a cache.
    module HttpGuard
      def get(url, options = {}, &block)
        context = Thread.current[:footlight_databus_replay]
        return super unless context && !Thread.current[:footlight_databus_transport]
        context.http_response(url, options)
      end

      def post(url, options = {}, &block)
        context = Thread.current[:footlight_databus_replay]
        return super unless context && !Thread.current[:footlight_databus_transport]
        context.http_response(url, options)
      end
    end

    module NetworkGuard
      def request(...)
        context = Thread.current[:footlight_databus_replay]
        if context && !Thread.current[:footlight_databus_transport]
          context.missing!("Unsupported direct network request during DSL replay: #{address}")
        end
        super
      end

      def connect
        context = Thread.current[:footlight_databus_replay]
        if context && !Thread.current[:footlight_databus_transport]
          context.missing!("Unsupported direct network request during DSL replay: #{address}")
        end
        super
      end

      private :connect
    end

    class CacheReader
      attr_reader :observations, :missing

      def initialize(base_url:, http_options: {}, api_inputs: {})
        @base_url = base_url.to_s.delete_suffix("/")
        raise ArgumentError, "Configure a remote Wringer URL" unless @base_url.match?(%r{\Ahttps?://})
        @http_options = http_options
        @bodies, @observations, @missing = {}, [], []
        @api_inputs = api_inputs.to_h.each_with_object({}) do |(url, input), inputs|
          uri = URI.parse(url.to_s)
          raise ArgumentError, "API snapshot needs an absolute HTTP(S) URL" unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.fragment.nil?
          input = input.to_h.symbolize_keys
          body = input.fetch(:body)
          raise ArgumentError, "API snapshot body must be a JSON string" unless body.is_a?(String)
          JSON.parse(body)
          captured_at = Time.iso8601(input.fetch(:captured_at).to_s).utc.iso8601
          provenance = input.fetch(:provenance).to_s
          raise ArgumentError, "API snapshot needs provenance" if provenance.blank?
          inputs[url.to_s] = { body: body.dup.freeze, captured_at: captured_at, provenance: provenance.dup.freeze }.freeze
        end
      end

      def missing!(reason)
        @missing << reason
        raise MissingInput, reason
      end

      def source_url
        uri = URI.parse(@base_url)
        uri.user = uri.password = uri.query = uri.fragment = nil
        uri.to_s
      end

      def fetch(url)
        key = Distillator::WringerUrlKey.legacy(url, include_fragment: true)
        return @bodies.fetch(key.uri_key).dup if @bodies.key?(key.uri_key)
        rows = request("/websites.json", term: key.uri_key)
        rows = rows.is_a?(Array) ? rows : [rows]
        row = rows.find { |item| item.is_a?(Hash) && item["uri"] == key.uri_key }
        missing!("Wringer cache entry missing: #{url}") unless row
        missing!("Wringer has no successful cached response: #{url}") unless row["successful_refresh"].present? && row["http_response_code"].to_i.between?(200, 299)

        # Require an existing successful record first. Never send expiry, force,
        # rendering or POST flags to /wring. Recheck the version after hydration.
        # /wring can fetch on a cache miss; a concurrent removal is therefore
        # detected and reported, rather than accepted as a historical replay.
        # Send the original input: Wringer performs its own one-pass decoding.
        # Sending normalized_url would decode reserved characters twice.
        payload = row["html"].present? ? row : request("/websites/wring.json", uri: url.to_s, include_fragment: true)
        after = request("/websites/#{Integer(row.fetch('id'))}.json")
        version = %w[id uri successful_refresh updated_at http_response_code]
        missing!("Wringer cache changed while reading: #{url}") unless row.slice(*version) == after.slice(*version)
        body = payload["html"] if payload.is_a?(Hash)
        missing!("Wringer cached body unavailable: #{url}") unless body.is_a?(String) && body.present?
        @observations << { url: url.to_s, canonical_url: key.normalized_url, cache_uri_key: key.uri_key,
          cache_id: row["id"], successful_refresh: row["successful_refresh"],
          bytes: body.bytesize, sha256: Digest::SHA256.hexdigest(body) }
        @bodies[key.uri_key] = body
        body.dup
      rescue MissingInput
        raise
      rescue StandardError => error
        missing!("Wringer cache read failed for #{url}: #{error.class}: #{error.message}")
      end

      def http_response(url, options)
        missing!("Cannot replay a request body from a URL-only cache: #{url}") if options[:body].present?
        # Match HTTParty's actual request URI without performing the request.
        # Decoding/re-encoding an existing query changes Wringer's exact key
        # (notably Culture3R's doWork::WSmap parameters and encoded spaces).
        target = HTTParty::Request.new(Net::HTTP::Get, url.to_s, options.dup).uri
        input = @api_inputs[target.to_s]
        if input
          body = input.fetch(:body).dup
          unless @observations.any? { |entry| entry[:source] == "supplied_api_snapshot" && entry[:url] == target.to_s }
            @observations << input.except(:body).merge(url: target.to_s, source: "supplied_api_snapshot",
              bytes: body.bytesize, sha256: Digest::SHA256.hexdigest(body))
          end
        else
          body = fetch(target.to_s)
        end
        response = Net::HTTPOK.new("1.1", "200", "OK")
        response.instance_variable_set(:@body, body)
        response.instance_variable_set(:@read, true)
        response["Content-Type"] = "application/json" if body.lstrip.start_with?("{", "[")
        request = Struct.new(:options).new({})
        HTTParty::Response.new(request, response, -> { JSON.parse(body) rescue body }, body: body)
      end

      def snapshot
        observations.map do |entry|
          body = if entry[:source] == "supplied_api_snapshot"
            @api_inputs.fetch(entry.fetch(:url)).fetch(:body)
          else
            key = Distillator::WringerUrlKey.legacy(entry.fetch(:url), include_fragment: true)
            @bodies.fetch(key.uri_key)
          end
          entry.merge(body_base64: Base64.strict_encode64(body))
        end
      end

      private

      def request(path, query = {})
        previous = Thread.current[:footlight_databus_transport]
        Thread.current[:footlight_databus_transport] = true
        response = HTTParty.get("#{@base_url}#{path}", @http_options.merge(query: query, timeout: 30, follow_redirects: false))
        raise "HTTP #{response.code} from Wringer inspection" unless response.code.to_i == 200
        response.parsed_response
      ensure
        Thread.current[:footlight_databus_transport] = previous
      end
    end

    class CacheRunner < Dsl::Core::AlgorithmRunner
      def initialize(context, reader:)
        @replay_reader = reader
        super(context)
      end

      private

      def fetch_result_for(url:, **)
        { status: :ok, body: @replay_reader.fetch(url), headers: {}, final_url: url, duration_ms: 0 }
      end
    end

    def self.call(**options) = new(**options).call

    def self.summary(report)
      { report_path: report[:report_path], baseline: report[:baseline], input_backend: report[:input_backend], wringer_url: report[:wringer_url],
        api_inputs: report.fetch(:api_inputs, []), sites: report[:sites].map do |site|
        site.slice(:seedurl, :rollout_mode, :export_date, :export_sha256, :production_source_evidence,
          :status, :selected_pages, :source_executions, :exact_match, :error).merge(
          data_added: Array(site[:data_added]).count, data_removed: Array(site[:data_removed]).count,
          input_or_extraction_errors: Array(site[:pages]).flat_map { |page| page[:errors].map { |error| error.merge(url: page[:url]) } }
            .group_by { |error| error.values_at(:url, :error) }.map do |(url, error), rows|
              rows.first.slice(:layer, :rdf_uri, :start_dates, :end_dates, :locations).merge(
                url: url, error: error, affected_sources: rows.count { |row| row[:source_id] },
                source_ids: rows.filter_map { |row| row[:source_id] }.uniq)
            end)
      end }
    end

    def initialize(manifest: nil, historical: false, sites: nil, per_site: 20, output_dir: nil, wringer_url: nil,
      reader: nil, export_loader: nil, progress: $stdout, api_inputs: {})
      raise ArgumentError, "Choose between 1 and 20 pages per site" unless per_site.is_a?(Integer) && per_site.between?(1, 20)
      if (manifest.nil? && !historical) || (manifest && historical)
        raise ArgumentError, "Pass a baseline manifest, or explicitly request historical: true for the original pilot"
      end
      if manifest && (wringer_url || reader || export_loader || api_inputs.present?)
        raise ArgumentError, "Manifest replay takes exports, Wringer and API inputs from the manifest"
      end
      @baseline = BaselineManifest.new(manifest) if manifest
      available_sites = @baseline ? @baseline.sites : HISTORICAL_EXPORTS.keys
      sites ||= available_sites
      unless sites.any? && sites.uniq == sites && (sites - available_sites).empty?
        raise ArgumentError, "Choose distinct sites from the baseline"
      end
      @sites, @per_site, @progress = sites, per_site, progress
      @output_dir = Pathname.new(output_dir || Rails.root.join("tmp", "databus-replay-#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{SecureRandom.hex(3)}"))
      # Pin input identity independently of rollout/compatibility configuration.
      # In particular, Shadow must not invoke native fetching or a shadow pair.
      raise ArgumentError, "Pass API snapshots to the custom reader itself" if reader && api_inputs.present?
      @reader = reader || CacheReader.new(base_url: @baseline&.wringer_url || wringer_url || DEFAULT_WRINGER_URL,
        api_inputs: @baseline ? @baseline.api_inputs : api_inputs)
      @export_loader = export_loader || lambda do |url|
        response = HTTParty.get(url, timeout: 60, follow_redirects: false)
        raise "Databus HTTP #{response.code}" unless response.code.to_i == 200
        response.body
      end
      @helper = Distillator::ComparisonRefreshProxy.new(context: ApplicationController.helpers, cookies: { dsl_trace: "false" })
    end

    def call
      raise "Run this replay in staging or an isolated test environment" unless Rails.env.staging? || Rails.env.test?
      connection = ActiveRecord::Base.connection
      raise "Start from a console with no open transaction" unless connection.open_transactions.zero?
      FileUtils.mkdir_p(@output_dir)
      install_guards
      write_file("baseline-manifest.json", @baseline.body) if @baseline
      report = { kind: "production_export_vs_staging_reextraction", dsl_contract: Dsl::Core::AlgorithmRunner::CONTRACT_VERSION,
        baseline: @baseline ? { kind: "pinned_manifest", captured_at: @baseline.captured_at, sha256: @baseline.sha256 } : { kind: "historical_pilot" },
        input_backend: "remote_wringer_cache", wringer_url: @reader.source_url,
        generated_at: Time.now.utc.iso8601, scope: "Selected source regeneration; preview statuses, no publication or statement saves",
        caveats: ["Historical HTML, source settings, manual corrections and reconciliation may have changed.",
          "Formatting and entity enrichment use current read-only lookup results, not a frozen production snapshot.",
          "Supplied API snapshots are separate inputs with recorded provenance; their capture time does not establish historical equivalence.",
          "Cache hydration checks existing entries and versions; the Wringer API has no atomic cache-only body endpoint."], sites: [] }
      connection.transaction do
        connection.execute("SET TRANSACTION READ ONLY")
        @sites.each do |seedurl|
          site_report = begin
            connection.transaction(requires_new: true) { replay_site(seedurl) }
          rescue StandardError => error
            { seedurl: seedurl, status: "incomplete", error: "#{error.class}: #{error.message}" }
          end
          report[:sites] << site_report
          write_json("report.json", report)
        end
        raise ActiveRecord::Rollback
      end
      report[:report_path] = @output_dir.join("report.json").to_s
      report[:cache_inputs] = @reader.observations
      report[:api_inputs] = @reader.observations.select { |entry| entry[:source] == "supplied_api_snapshot" }
      report[:reconciliation_performance] = @helper.reconciliation_performance
      write_json("cache-inputs.json", @reader.snapshot)
      write_json("report.json", report)
      report
    end

    private

    def install_guards
      HTTParty.singleton_class.prepend(HttpGuard) unless HTTParty.singleton_class.ancestors.include?(HttpGuard)
      Net::HTTP.prepend(NetworkGuard) unless Net::HTTP.ancestors.include?(NetworkGuard)
    end

    def replay_site(seedurl)
      website = Website.find_by!(seedurl: seedurl)
      raise "#{seedurl} must be Legacy or Shadow for this replay (current: #{website.distillator_mode})" unless website.distillator_mode.in?(%w[legacy shadow])
      if @baseline
        date, url, body = @baseline.export(seedurl).values_at(:date, :url, :body)
        production_sources = @baseline.production_sources(seedurl)
      else
        date = HISTORICAL_EXPORTS.fetch(seedurl)
        url = "https://data.culturecreates.com/databus/culture-creates/footlight/#{seedurl}/#{date}/#{seedurl}.json"
        body = @export_loader.call(url)
      end
      write_file("#{seedurl}-production.json", body)
      if production_sources
        write_file("#{seedurl}-production-sources.json", production_sources.fetch(:body))
      end
      baseline = RDF::Graph.new.insert(*JSON::LD::API.toRdf(JSON.parse(body)).to_a)
      candidates = event_source_urls(baseline)
      chosen = evenly_sample(candidates, @per_site)
      raise "Export contains no event source URLs" if chosen.empty?
      pages = chosen.map.with_index do |page_url, index|
        @progress&.puts "#{seedurl}: #{index + 1}/#{chosen.size} #{page_url}"
        extract_page(website, page_url)
      end
      source_ids = pages.flat_map { |page| page[:sources].map { |source| source[:source_id] } }.uniq
      write_json("#{seedurl}-selected-sources.json", Source.where(id: source_ids).includes(property: :rdfs_class).map do |source|
        { source: source.attributes, property: source.property.attributes, rdfs_class: source.property.rdfs_class.attributes }
      end)
      expected = sampled_graph(baseline, chosen)
      @progress&.puts "#{seedurl}: generating RDF with linked local resource descriptions"
      actual = generate_graph(pages)
      write_file("#{seedurl}-expected.nq", expected.dump(:nquads))
      write_file("#{seedurl}-actual.nq", actual.dump(:nquads))
      write_json("#{seedurl}-extraction.json", pages.map { |page| page.except(:statements) })
      @progress&.puts "#{seedurl}: comparing generated RDF with the production export"
      diff = graph_difference(expected, actual)
      incomplete = pages.any? { |page| page[:errors].any? }
      { seedurl: seedurl, rollout_mode: website.distillator_mode, export_date: date, export_url: url, export_sha256: Digest::SHA256.hexdigest(body),
        production_source_evidence: production_sources ? production_sources.except(:body) : "missing",
        available_pages: candidates.count, selected_pages: chosen.count, source_executions: pages.sum { |page| page[:sources].count },
        status: incomplete ? "incomplete" : (diff[:equivalent_event_data] ? "equivalent_event_data" : "differences_need_review"),
        pages: pages.map { |page| page.slice(:url, :errors, :sources) }, **diff }
    rescue ActiveRecord::StatementInvalid
      raise
    rescue StandardError => error
      { seedurl: seedurl, status: "incomplete", error: "#{error.class}: #{error.message}" }
    end

    def event_source_urls(graph)
      roots = event_subjects(graph)
      roots.flat_map do |root|
        graph.query([root, RDF::URI("#{SCHEMA}mainEntityOfPage"), nil]).flat_map do |triple|
          graph.query([triple.object, RDF::URI("#{SCHEMA}url"), nil]).map { |statement| statement.object.to_s }
        end + graph.query([root, RDF::URI("#{SCHEMA}url"), nil]).map { |statement| statement.object.to_s }
      end.select { |url| url.match?(%r{\Ahttps?://}) }.uniq.sort
    end

    def event_subjects(graph)
      %w[Event EventSeries].flat_map { |type| graph.query([nil, RDF.type, RDF::URI("#{SCHEMA}#{type}")]).map(&:subject) }.uniq
    end

    def evenly_sample(values, count)
      return values if values.count <= count
      return [values.first] if count == 1
      count.times.map { |index| values[(index * (values.count - 1).to_f / (count - 1)).round] }
    end

    def sampled_graph(graph, urls)
      roots = event_subjects(graph).select do |root|
        graph.query([root, RDF::URI("#{SCHEMA}url"), nil]).any? { |triple| urls.include?(triple.object.to_s) } ||
          graph.query([root, RDF::URI("#{SCHEMA}mainEntityOfPage"), nil]).any? do |triple|
            graph.query([triple.object, RDF::URI("#{SCHEMA}url"), nil]).any? { |statement| urls.include?(statement.object.to_s) }
          end
      end
      result, visited, queue = RDF::Graph.new, {}, roots.dup
      until queue.empty?
        subject = queue.shift
        next if visited[subject]
        visited[subject] = true
        graph.query([subject, nil, nil]).each do |triple|
          result << triple
          queue << triple.object if triple.object.resource? && !visited[triple.object]
        end
      end
      result
    end

    def extract_page(website, url)
      page = { url: url, errors: [], sources: [], statements: [] }
      matches = website.webpages.where(url: url).to_a
      raise "Expected exactly one staging webpage, found #{matches.count}" unless matches.one?
      webpage = matches.first
      sources = Statements::RefreshWebpageStatementsService.sources_for_webpage(webpage, default_language: website.default_language).select(&:selected?)
      raise "No selected sources for staging webpage" if sources.empty?
      sources.each do |source|
        entry = { source_id: source.id, property: source.property.label, language: source.language,
          algorithm_sha256: Digest::SHA256.hexdigest(source.algorithm_value.to_s) }
        page[:sources] << entry
        begin
          before_missing = @reader.missing.length
          raw = with_cache_only do
            runner = CacheRunner.new({ url: url, render_js: source.render_js, scrape_options: {}, tracer: Dsl::Tracing::NullTracer.new }, reader: @reader)
            value = runner.run(source.algorithm_value)
            entry[:library_evidence] = runner.library_evidence if runner.library_evidence.present?
            value
          end
          raise MissingInput, @reader.missing[before_missing..].join("; ") if @reader.missing.length > before_missing
          entry[:raw] = raw
          raise "DSL aborted: #{raw.last.inspect}" if abort_result?(raw)
          formatted = @helper.format_datatype(raw.deep_dup, source.property, webpage, statement_status: "initial")
          entry[:formatted] = formatted
          raise "Formatting aborted: #{formatted.last.inspect}" if abort_result?(formatted)
          existing = Statement.find_by(webpage_id: webpage.id, source_id: source.id)
          entry[:existing_manual_correction] = existing&.manual || false
          # Construct new, unsaved values. Never fall back to an existing cache.
          statement = Statement.new(source: source, webpage: webpage, selected_individual: true,
            manual: false, status: "updated", cache: formatted, cache_refreshed: Time.current)
          page[:statements] << statement
        rescue ActiveRecord::StatementInvalid
          raise
        rescue StandardError => error
          page[:errors] << entry.slice(:source_id, :property).merge(error: "#{error.class}: #{error.message}")
        end
      end
      page
    rescue ActiveRecord::StatementInvalid
      raise
    rescue StandardError => error
      page[:errors] << { error: "#{error.class}: #{error.message}" }
      page
    end

    def with_cache_only
      previous = Thread.current[:footlight_databus_replay]
      Thread.current[:footlight_databus_replay] = @reader
      yield
    ensure
      Thread.current[:footlight_databus_replay] = previous
    end

    def abort_result?(value) = value.is_a?(Array) && value.first == "abort_update"

    def generate_graph(pages)
      graph = RDF::Graph.new
      statements = pages.flat_map { |page| page[:statements] }
      statements.group_by { |statement| statement.webpage.rdf_uri }.each do |uri, group|
        data = group.map { |statement| JsonldGenerator.adjust_labels_for_api(statement, subject: uri, webpage_class_name: statement.webpage.rdfs_class.name) }
        event_graph = JsonldGenerator.build_graph(data, for_artsdata: true)
        %i[make_contact_series make_offer_series make_event_series].each { |method| event_graph = JsonldGenerator.public_send(method, event_graph, uri) }
        graph << event_graph
      rescue JsonldGenerator::EventSeriesConversionError => error
        pages.select { |page| page[:statements].any? { |statement| statement.webpage.rdf_uri == uri } }.each do |page|
          page[:errors] << { layer: "export", rdf_uri: error.rdf_uri,
            start_dates: error.start_dates, end_dates: error.end_dates, locations: error.locations,
            error: "#{error.class}: #{error.message}" }
        end
      end
      graph = JsonldGenerator.add_triples_from_footlight(graph)
      JsonldGenerator.remove_annotations(graph)
    end

    def graph_difference(expected, actual)
      old_lines, new_lines = canonical_lines(expected), canonical_lines(actual)
      # lastReviewed is generated from refresh time. Retain its exact differences
      # in the audit while separately comparing actual event content.
      without_review = lambda do |graph|
        RDF::Graph.new.insert(*graph.reject { |triple| triple.predicate == RDF::URI("#{SCHEMA}lastReviewed") })
      end
      old_data, new_data = canonical_lines(without_review.call(expected)), canonical_lines(without_review.call(actual))
      { exact_match: old_lines == new_lines, equivalent_event_data: old_data == new_data,
        expected_triples: expected.count, actual_triples: actual.count,
        data_added: new_data - old_data, data_removed: old_data - new_data,
        exact_added: new_lines - old_lines, exact_removed: old_lines - new_lines }
    end

    def canonical_lines(graph) = graph.dump(:normalize, algorithm: :rdfc10).lines.map(&:strip).sort
    # Preserve HTTP response bytes even when the client tags UTF-8 JSON as
    # ASCII-8BIT. Text-mode writes attempt an invalid binary-to-UTF-8 transcode.
    def write_file(name, value) = @output_dir.join(name).binwrite(value)
    def write_json(name, value) = write_file(name, JSON.pretty_generate(value) + "\n")
  end
end
