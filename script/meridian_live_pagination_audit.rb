# frozen_string_literal: true

# Read-only, bounded Meridian calendar capture. Default audits four pages;
# --full requires explicit live terminal-page evidence (up to 25 pages/language).
# Uses selected URL Source XPath only (NOT its ruby= step).
# No result from this probe is authoritative discovery/archival evidence.
# bin/rails runner script/meridian_live_pagination_audit.rb --json /tmp/meridian-live.json
require "digest"
require "json"
require "net/http"
require "nokogiri"
require "optparse"
require "uri"

module MeridianLivePaginationAudit
  ROOT = "https://meridiancentrepointe.com"
  PATHS = { "en" => "/en/events", "fr" => "/fr/evenements" }.freeze
  MAX_HTML_BYTES = 5 * 1024 * 1024
  MAX_PAGES = ResourceLists::MeridianPager::MAX_PAGES
  AUDIT_PAGES = (0..1).freeze

  module_function

  # Pure testable content-evidence gate; the selected Source XPath is checked
  # separately to establish that this page actually contains event URLs.
  def validate_calendar_html!(html, _page_url, _language)
    validated = ResourceLists::MeridianPageValidation.call(html: html)
    { title: validated.title, page_evidence: validated.page_evidence }
  end

  def snapshot_page(path)
    raise "Snapshot missing: #{path}" unless File.file?(path)
    html = File.binread(path)
    raise "Empty or oversized snapshot" unless html.bytesize.between?(1, MAX_HTML_BYTES)
    { html: html, sha256: Digest::SHA256.hexdigest(html), final_url: nil,
      content_type: "text/html (operator-supplied)", bytes: html.bytesize, capture_mode: "operator_snapshot" }
  end

  def selected_url_source(website, page)
    selected = page.statements.joins(source: :property)
      .where(selected_individual: true, sources: { selected: true, website_id: website.id },
        properties: { label: "Webpage URL List" }).includes(:source).to_a
    raise "RL #{page.id}: expected one selected Webpage URL List, got #{selected.size}" unless selected.one?

    source = selected.first.source
    raise "RL #{page.id}: render_js=true; HTML-only extraction cannot claim parity" if source.render_js

    steps = source.algorithm_value.to_s.split(";").map { |step| step.strip.partition("=") }
    xpaths = steps.filter_map { |kind, separator, value| value if kind == "xpath" && separator == "=" }
    raise "RL #{page.id}: expected one xpath= step, got #{xpaths.size}" unless xpaths.one?
    raise "RL #{page.id}: XPath must select URL attributes" unless xpaths.first.match?(%r{/(?:@href|@src)\s*\z})

    { xpath: xpaths.first, source_id: source.id,
      source_sha256: Digest::SHA256.hexdigest(source.algorithm_value.to_s),
      note: "XPath only; url= and ruby= processing are NOT executed" }
  end

  def canonical_event_url(value, page_url, language)
    raw = value.to_s.strip
    return nil if raw.empty?
    uri = URI.join(page_url, raw)
    root = URI.parse(ROOT)
    return nil unless uri.scheme == "https" && uri.host == root.host && uri.port == root.port && uri.userinfo.nil?
    return nil unless uri.path.start_with?("/#{language}/") && uri.path != PATHS.fetch(language)
    return nil if uri.fragment

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def fetch_page(url)
    original = URI.parse(url)
    current = original
    3.times do |attempt|
      response = Net::HTTP.start(current.host, current.port, use_ssl: true,
        open_timeout: 10, read_timeout: 25, write_timeout: 10) do |http|
        request = Net::HTTP::Get.new(current.request_uri)
        request["User-Agent"] = "Footlight-Meridian-QA/1.0 (read-only inventory audit)"
        request["Accept"] = "text/html"
        request["Accept-Encoding"] = "identity"
        http.request(request)
      end
      if response.is_a?(Net::HTTPRedirection)
        raise "too many redirects" if attempt == 2
        location = response["location"] or raise "redirect without location"
        candidate = URI.join(current.to_s, location)
        raise "redirect changed calendar page" unless candidate.scheme == "https" &&
          candidate.host == original.host && candidate.port == original.port &&
          candidate.userinfo.nil? && candidate.path.sub(%r{/+\z}, "") == original.path.sub(%r{/+\z}, "") &&
          URI.decode_www_form(candidate.query.to_s).sort == URI.decode_www_form(original.query.to_s).sort
        current = candidate
        next
      end
      raise "HTTP #{response.code}" unless response.code.to_i == 200
      body = response.body.to_s
      raise "empty or oversized HTML (#{body.bytesize} bytes)" unless body.bytesize.between?(1, MAX_HTML_BYTES)
      content_type = response["content-type"].to_s
      raise "unexpected content type #{content_type.inspect}" unless content_type.downcase.include?("html")
      return { html: body, sha256: Digest::SHA256.hexdigest(body), final_url: current.to_s,
        content_type: content_type, bytes: body.bytesize }
    end
  end

  def extract_page(html, page_url, language, xpath)
    document = Nokogiri::HTML(html)
    nodes = document.xpath(xpath)
    urls, invalid = [], []
    nodes.each do |node|
      value = node.text.to_s.strip
      url = canonical_event_url(value, page_url, language)
      url ? urls << url : invalid << value[0, 120]
    end
    pager = document.xpath("//a[@href]").filter_map do |node|
      uri = URI.join(page_url, node["href"])
      next unless uri.scheme == "https" && uri.host == URI.parse(ROOT).host && uri.path == PATHS.fetch(language)
      page_values = URI.decode_www_form(uri.query.to_s).filter_map { |key, value| value if key == "page" }
      page_values.first.to_i if page_values.one? && page_values.first.match?(/\A(?:0|[1-9]\d*)\z/)
    rescue URI::InvalidURIError, ArgumentError
      nil
    end.uniq.sort
    { xpath_hits: nodes.size, urls: urls.uniq, duplicates_within_page: urls.size - urls.uniq.size,
      rejected_xpath_values: invalid.first(10), pager_page_numbers: pager }
  rescue Nokogiri::XML::XPath::SyntaxError => error
    raise "invalid selected Source XPath: #{error.message}"
  end

  def run(output: nil, snapshots: {}, full: false)
    connection = ActiveRecord::Base.connection
    raise "Refusing production" if Rails.env.production?
    allowed = connection.current_database == "footlight_condenser_staging_work" ||
      connection.current_database.match?(/\Afootlight_condenser_[a-z0-9_]*qa\z/)
    raise "Expected a local staging working or QA database" unless allowed
    raise "Full live pagination cannot use four-page snapshots" if full && snapshots.any?
    expected = PATHS.keys.product(AUDIT_PAGES.to_a)
    if snapshots.any? && snapshots.keys.sort != expected.sort
      raise "For replay, all four contemporaneous EN/FR page 0/1 HTML snapshots are required"
    end
    raise "Refusing overwrite: #{output}" if output && File.exist?(output)

    report = { generated_at: Time.current.utc.iso8601, database: connection.current_database,
      site: "meridiancentrepointe-com", read_only: true, pages: {}, errors: [],
      inventory_authoritative: false, terminal_evidence: "NOT_ESTABLISHED",
      execution: "Selected Source XPath only; no Ruby DSL, imports, cache writes, or new RDF identities",
      input_mode: snapshots.empty? ? (full ? "live_full_bounded" : "live_four_page_sample") : "operator_snapshots_not_live_proof" }
    connection.transaction do
      connection.execute("SET TRANSACTION READ ONLY")
      site = Website.find_by!(seedurl: report.fetch(:site))
      rlist = RdfsClass.find_by!(name: "ResourceList")
      existing_lists = site.webpages.where(rdfs_class_id: rlist.id).includes(:statements).to_a
      source_by_language = PATHS.to_h do |language, path|
        pages = existing_lists.select { |page| page.language == language && page.url == ROOT + path }
        raise "Expected one original #{language} ResourceList, got #{pages.size}" unless pages.one?
        [language, selected_url_source(site, pages.first)]
      end

      PATHS.each do |language, path|
        report[:pages][language] = {}
        numbers = full ? [0] : AUDIT_PAGES.to_a
        last_page = nil
        position = 0
        while position < numbers.length
          number = numbers.fetch(position)
          url = "#{ROOT}#{path}?page=#{number}"
          begin
            snapshot_path = snapshots[[language, number]]
            fetched = snapshot_path ? snapshot_page(snapshot_path) : fetch_page(url)
            identity = validate_calendar_html!(fetched.fetch(:html), url, language)
            pager = ResourceLists::MeridianPager.call(html: fetched.fetch(:html), url: url)
            extracted = extract_page(fetched.fetch(:html), url, language, source_by_language.fetch(language).fetch(:xpath))
            raise "no event links from selected XPath" if extracted.fetch(:urls).empty?
            raise "out-of-scope or malformed XPath values" if extracted.fetch(:rejected_xpath_values).any?

            if full
              if number == 0
                last_page = pager.last_page
                raise "No explicit last-page navigation on first page" if last_page.nil?
                raise "Out-of-range terminal page #{last_page}" unless last_page.between?(0, MAX_PAGES - 1)
                numbers = (0..last_page).to_a
              else
                raise "Pager last-page changed mid-capture" if pager.last_page && pager.last_page != last_page
                raise "Last page still links to a next page" if number == last_page && pager.next_page
              end
            end

            report[:pages][language][number] = { url: url, http: snapshot_path ? nil : 200, sha256: fetched.fetch(:sha256),
              bytes: fetched.fetch(:bytes), final_url: fetched.fetch(:final_url), capture_mode: fetched[:capture_mode] || "live_http",
              source_id: source_by_language.fetch(language).fetch(:source_id),
              source_sha256: source_by_language.fetch(language).fetch(:source_sha256),
              captured_at: Time.current.utc.iso8601, **identity, **extracted,
              pager_last_page: pager.last_page, pager_next_page: pager.next_page }
          rescue StandardError => error
            report[:errors] << "#{language} page #{number}: #{error.class}: #{error.message}"
            report[:pages][language][number] = { url: url, status: "blocked", error: error.class.name }
            break if full
          end
          position += 1
        end

        if full && !last_page.nil? && report[:pages][language].keys.sort == (0..last_page).to_a &&
            report[:pages][language].values.none? { |row| row[:status] == "blocked" }
          report[:terminal_evidence] = {} if report[:terminal_evidence].is_a?(String)
          report[:terminal_evidence][language] = { last_page: last_page, expected_pages: last_page + 1,
            verified_pages: report[:pages][language].size,
            note: "Explicit last-page link plus all numbered responses. Not an atomic snapshot." }
        end
      end

      all_records = report[:pages].flat_map do |language, pages|
        pages.flat_map do |number, entry|
          Array(entry[:urls]).map { |url| { language: language, page: number, url: url } }
        end
      end
      urls = all_records.map { |record| record.fetch(:url) }.uniq
      found = site.webpages.event_pages.where(url: urls).pluck(:url, :rdf_uri, :language, :archive_date)
      known = found.to_h { |url, rdf_uri, language, archive| [url, { rdf_uri: rdf_uri, language: language, active: archive.nil? || archive > Time.current }] }
      all_records.each do |record|
        page = known[record.fetch(:url)]
        record[:rdf_uri] = page[:rdf_uri] if page
        record[:existing_active] = page[:active] if page
        if page && page[:language] != record[:language]
          report[:errors] << "Stored Webpage language mismatch: #{record.fetch(:url)}"
        end
      end
      known_pairs = all_records.select { |record| record[:rdf_uri] }.group_by { |record| record.fetch(:rdf_uri) }
      paired = known_pairs.filter_map do |rdf_uri, records|
        by_language = records.group_by { |record| record.fetch(:language) }
        next unless by_language.keys.sort == %w[en fr]
        { rdf_uri: rdf_uri, en_pages: by_language.fetch("en").map { |row| row[:page] }.uniq.sort,
          fr_pages: by_language.fetch("fr").map { |row| row[:page] }.uniq.sort }
      end
      unmatched = known_pairs.filter_map do |rdf_uri, records|
        langs = records.map { |record| record[:language] }.uniq.sort
        { rdf_uri: rdf_uri, found_languages: langs } unless langs == %w[en fr]
      end
      new_urls = all_records.reject { |record| record[:rdf_uri] }
      repeated = all_records.group_by { |record| [record[:language], record[:url]] }
        .filter_map { |(_, url), occurrences| { language: occurrences.first[:language], url: url,
          pages: occurrences.map { |row| row[:page] }.uniq.sort } if occurrences.size > 1 }
      report[:reconciliation] = {
        count_by_language: PATHS.keys.to_h { |language| [language, all_records.select { |row| row[:language] == language }.map { |row| row[:url] }.uniq.size] },
        existing_bilingual_rdf_pairs: paired.size, cross_page_rdf_pairs: paired.count { |pair| pair[:en_pages] != pair[:fr_pages] },
        paired_existing_identities: paired, unmatched_existing_identities: unmatched,
        new_or_unmapped_urls: new_urls, duplicate_urls_across_pages: repeated
      }
      terminal_verified = full && report[:terminal_evidence].is_a?(Hash) &&
        report[:terminal_evidence].keys.sort == PATHS.keys.sort
      report[:pairing_review] = {
        terminal_verified: terminal_verified,
        existing_pairs_verified: terminal_verified && report[:errors].empty? &&
          unmatched.empty? && new_urls.empty? && !paired.empty?,
        unmapped_urls: new_urls.length,
        unmatched_existing_identities: unmatched.length,
        note: "Existing RDF identities only. New-event keys and URI minting remain unverified."
      }
      report[:status] = report[:errors].empty? ? "diagnostic_only" : "blocked"
    end
    puts "Database: #{report[:database]} | #{report[:site]} | READ-ONLY | #{report[:status]}"
    report[:pages].each do |language, pages|
      pages.each do |number, row|
        puts "#{language.upcase} page #{number}: #{row[:status] || '200'} XPath hits=#{row[:xpath_hits] || '?'} URLs=#{row[:urls]&.size || '?'} pager=#{row[:pager_page_numbers]&.inspect || '?'}"
      end
    end
    r = report[:reconciliation]
    puts "URLs: #{r[:count_by_language]} | existing bilingual RDF pairs: #{r[:existing_bilingual_rdf_pairs]} | cross-page: #{r[:cross_page_rdf_pairs]}"
    puts "Unmapped URLs: #{r[:new_or_unmapped_urls].size} | unmatched existing RDF: #{r[:unmatched_existing_identities].size} | repeated URLs: #{r[:duplicate_urls_across_pages].size}"
    puts "Existing pairing review: #{report[:pairing_review].inspect}"
    report[:errors].each { |error| warn "BLOCKED: #{error}" }
    puts "Live terminal proof: #{report[:terminal_evidence]}; no import or mutation"
    if output
      File.write(output, JSON.pretty_generate(report) + "\n")
      puts "Saved #{output} (local file only)"
    end
    report
  end
end

output = nil
full = false
snapshots = {}
OptionParser.new do |opts|
  opts.on("--json PATH") { |path| output = path }
  opts.on("--full", "Follow the explicit last-page link, max 25 pages per language") { full = true }
  opts.on("--html LANG:PAGE:PATH", "Read-only replay of all 4 contemporaneous HTML captures") do |spec|
    lang, number, path = spec.split(":", 3)
    abort "Invalid --html: #{spec}" unless MeridianLivePaginationAudit::PATHS.key?(lang) &&
      %w[0 1].include?(number) && path.present? && !snapshots.key?([lang, number.to_i])
    snapshots[[lang, number.to_i]] = path
  end
end.parse!(ARGV)
abort "Unexpected arguments" unless ARGV.empty?
MeridianLivePaginationAudit.run(output: output, snapshots: snapshots, full: full)
