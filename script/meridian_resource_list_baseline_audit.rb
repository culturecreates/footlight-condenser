# frozen_string_literal: true

# Read-only inventory of Meridian's current selected RL URL/URI positional
# mapping, and active versus archived bilingual Title identities.
# This is baseline evidence, NOT live capture or pagination completeness proof.
# Usage: bin/rails runner script/meridian_resource_list_baseline_audit.rb --json /tmp/meridian-baseline-audit.json
require "json"
require "digest"
require "optparse"

output = nil
OptionParser.new { |opts| opts.on("--json PATH") { |path| output = path } }.parse!(ARGV)
abort "Unexpected arguments" unless ARGV.empty?
abort "Refusing production" if Rails.env.production?
abort "Refusing overwrite: #{output}" if output && File.exist?(output)

report = nil
ActiveRecord::Base.connection.transaction do
  ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")
  site = Website.find_by!(seedurl: "meridiancentrepointe-com")
  event_class = RdfsClass.find_by!(name: "Event")
  rl_class = RdfsClass.find_by!(name: "ResourceList")
  labels = ["Webpage URL List", "URI List"].freeze
  rl_pages = site.webpages.where(rdfs_class_id: rl_class.id).order(:id).to_a
  entries, errors, sources = [], [], []

  rl_pages.each do |rl|
    selected = rl.statements.joins(source: :property)
      .where(selected_individual: true, sources: { selected: true, website_id: site.id }, properties: { label: labels })
      .includes(source: :property).to_a
    by_label = selected.group_by { |statement| statement.source.property.label }
    values = {}
    labels.each do |label|
      statements = by_label.fetch(label, [])
      errors << "RL #{rl.id}: expected exactly one selected #{label} (got #{statements.size})" unless statements.one?
      next unless statements.one?
      statement = statements.first
      source = statement.source
      parsed = begin
        JSON.parse(statement.cache.to_s)
      rescue JSON::ParserError
        nil
      end
      errors << "RL #{rl.id} #{label}: invalid JSON string array" unless parsed.is_a?(Array) && parsed.all? { |value| value.is_a?(String) && !value.empty? }
      values[label] = parsed if parsed.is_a?(Array) && parsed.all? { |value| value.is_a?(String) && !value.empty? }
      sources << { rl_id: rl.id, rl_language: rl.language, source_id: source.id, source_language: source.language,
        property: label, statement_id: statement.id, status: statement.status,
        count: parsed.is_a?(Array) ? parsed.size : nil,
        algorithm_sha256: Digest::SHA256.hexdigest(source.algorithm_value.to_s),
        # Diagnostic only: never execute arbitrary stored DSL in this script.
        algorithm_steps: source.algorithm_value.to_s.scan(/(?:\A|;)\s*([a-z][a-z0-9_]*)=/i).flatten.uniq }
    end
    next unless values.keys.sort == labels.sort
    urls, uris = values.values_at("Webpage URL List", "URI List")
    errors << "RL #{rl.id}: URL/URI list counts differ #{urls.size}/#{uris.size}" unless urls.size == uris.size
    urls.zip(uris).each_with_index do |(url, uri), index|
      next unless url && uri
      entries << { rl_id: rl.id, language: rl.language, position: index, url: url, rdf_uri: uri }
    end
  end

  by_url = entries.group_by { |row| row[:url] }
  url_conflicts = by_url.filter_map do |url, rows|
    rdf_uris = rows.map { |row| row[:rdf_uri] }.uniq
    { url: url, rdf_uris: rdf_uris } if rdf_uris.size > 1
  end
  current_events = site.webpages.event_pages.where(url: by_url.keys).pluck(:url, :language, :rdf_uri)
  events_by_url = current_events.group_by(&:first)
  missing_urls = by_url.keys - events_by_url.keys
  mismatches = entries.filter_map do |row|
    matches = events_by_url.fetch(row[:url], [])
    next if matches.empty? || matches.any? { |_, _, rdf| rdf == row[:rdf_uri] }
    { url: row[:url], cached_rdf: row[:rdf_uri], existing_rdf: matches.map(&:last).uniq }
  end.uniq

  now = Time.current
  titles = Statement.joins(:webpage, source: :property)
    .where(webpages: { website_id: site.id, rdfs_class_id: event_class.id },
      sources: { website_id: site.id, selected: true }, properties: { label: "Title", rdfs_class_id: event_class.id },
      statements: { status: %w[ok updated] })
    .where.not(statements: { cache: [nil, "", "[]"] })
    .pluck("webpages.rdf_uri", "webpages.language", "sources.language", "statements.selected_individual", "webpages.archive_date")
  valid_language = ->(value) { lang = value.to_s.downcase.split(/[-_]/).first; %w[en fr].include?(lang) ? lang : nil }
  paired = ->(rows, column, active:, chosen:) do
    rows.group_by(&:first).count do |_, records|
      considered = records.select { |row| (!active || row[4].nil? || row[4] > now) && (!chosen || row[3] == true) }
      languages = considered.filter_map { |row| valid_language.call(row[column]) }.uniq
      (languages & %w[en fr]).size == 2
    end
  end
  identities = {
    all_page_language: paired.call(titles, 1, active: false, chosen: true),
    active_page_language: paired.call(titles, 1, active: true, chosen: true),
    all_source_language: paired.call(titles, 2, active: false, chosen: false),
    active_source_language: paired.call(titles, 2, active: true, chosen: false),
    active_selected_source_language: paired.call(titles, 2, active: true, chosen: true)
  }

  report = {
    generated_at: Time.current.utc.iso8601, database: ActiveRecord::Base.connection.current_database,
    website: { id: site.id, seedurl: site.seedurl }, read_only: true,
    rl_counts: rl_pages.group_by(&:language).transform_values(&:size),
    selected_sources: sources, rl_entries: entries, rl_errors: errors, url_rdf_conflicts: url_conflicts,
    missing_event_webpage_urls: missing_urls, cache_to_webpage_rdf_mismatches: mismatches,
    title_rdf_identity_counts: identities,
    note: "Cached RL values are historical. No live page fetched, no terminal evidence, no DB mutation."
  }
end

puts "Database: #{report[:database]} | #{report.dig(:website, :seedurl)} | READ-ONLY"
puts "Cached URL/RDF entries: #{report[:rl_entries].size} | RL errors: #{report[:rl_errors].size} | URL-RDF conflicts: #{report[:url_rdf_conflicts].size}"
puts "Existing Webpages absent for cached URLs: #{report[:missing_event_webpage_urls].size} | RDF mismatches: #{report[:cache_to_webpage_rdf_mismatches].size}"
report[:selected_sources].each do |source|
  puts "  RL #{source[:rl_id]} #{source[:property]} #{source[:source_language]} count=#{source[:count]} DSL ops=#{source[:algorithm_steps].join(',')} sha=#{source[:algorithm_sha256][0, 12]}"
end
puts "Bilingual Title RDF identities: #{report[:title_rdf_identity_counts].map { |kind, count| "#{kind}=#{count}" }.join(' | ')}"
report[:rl_errors].each { |error| puts "ERROR: #{error}" }
if output
  File.write(output, JSON.pretty_generate(report) + "\n")
  puts "Saved #{output} (local file only)"
end
