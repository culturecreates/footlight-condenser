# frozen_string_literal: true

# Read-only Meridian QA preflight. Never creates/refreshes Webpages or Statements.
# Usage: bin/rails runner script/meridian_resource_list_preflight.rb [--json /tmp/meridian-qa.json]
require "json"
require "digest"
require "optparse"

output = nil
OptionParser.new do |opts|
  opts.on("--json PATH") { |path| output = path }
end.parse!(ARGV)
abort "Unexpected arguments: #{ARGV.inspect}" unless ARGV.empty?
abort "Refusing production" if Rails.env.production?

root = "https://meridiancentrepointe.com"
paths = { "en" => "/en/events", "fr" => "/fr/evenements" }.freeze
report = nil

ActiveRecord::Base.connection.transaction do
  ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")
  website = Website.find_by!(seedurl: "meridiancentrepointe-com")
  list_class = RdfsClass.find_by!(name: "ResourceList")
  event_class = RdfsClass.find_by!(name: "Event")
  lists = website.webpages.where(rdfs_class_id: list_class.id).includes(statements: { source: :property }).order(:id).to_a

  plan = paths.to_h do |language, path|
    expected = (0..1).map { |number| "#{root}#{path}?page=#{number}" }
    configured = ResourceLists::ConfiguredCalendarPages.call(
      webpages: expected.map { |url| Struct.new(:url).new(url) }, root: root, path: path, first_page: 0
    )
    abort "Invalid #{language} calendar page configuration: #{configured.errors.inspect}" unless configured.valid?
    [language, configured.pages.map do |page|
      { number: page.number, url: page.url, current_rl_id: lists.find { |item| item.url == page.url }&.id }
    end]
  end

  selected = lists.flat_map do |page|
    page.statements.filter_map do |statement|
      source = statement.source
      next unless statement.selected_individual && source&.selected && source.website_id == website.id
      next unless ["Webpage URL List", "URI List"].include?(source.property&.label)
      parsed_count = begin
        value = JSON.parse(statement.cache.to_s)
        value.size if value.is_a?(Array)
      rescue JSON::ParserError
        nil
      end
      { webpage_id: page.id, url: page.url, webpage_language: page.language, source_id: source.id,
        source_language: source.language, property: source.property.label, statement_id: statement.id,
        selected_count: parsed_count, status: statement.status, render_js: source.render_js,
        algorithm_digest: Digest::SHA256.hexdigest(source.algorithm_value.to_s) }
    end
  end

  title_rows = Statement.joins(:webpage, source: :property)
    .where(webpages: { website_id: website.id, rdfs_class_id: event_class.id },
      sources: { website_id: website.id, selected: true },
      properties: { label: "Title" }, statements: { selected_individual: true, status: %w[ok updated] })
    .where.not(statements: { cache: [nil, "", "[]"] })
    .pluck("webpages.rdf_uri", "webpages.language", "webpages.url")
  bilingual = title_rows.group_by(&:first).filter_map do |rdf_uri, rows|
    next unless %w[en fr].all? { |lang| rows.any? { |row| row[1].to_s.downcase == lang } }
    { rdf_uri: rdf_uri, urls: rows.group_by { |row| row[1] }.transform_values { |v| v.map(&:last).uniq.sort } }
  end

  report = {
    database: ActiveRecord::Base.connection.current_database, read_only: true,
    website: { id: website.id, seedurl: website.seedurl },
    expected_pages: plan,
    current_lists: lists.map { |page| { id: page.id, url: page.url, language: page.language,
      active: page.archive_date.nil? || page.archive_date > Time.current } },
    selected_list_sources: selected, paired_title_rdf_count: bilingual.size,
    paired_title_rdf: bilingual,
    completeness: "UNVERIFIED: no live fetch, extraction or terminal-page evidence",
    modifications: "NONE"
  }
end

puts "Database: #{report[:database]} | #{report.dig(:website, :seedurl)} | READ-ONLY"
report[:expected_pages].each do |language, pages|
  pages.each { |page| puts "#{language.upcase} page #{page[:number]}: #{page[:url]} (existing RL: #{page[:current_rl_id] || 'none'})" }
end
puts "ResourceLists: #{report[:current_lists].size}, selected RL source statements: #{report[:selected_list_sources].size}"
report[:selected_list_sources].each do |row|
  puts "  RL #{row[:webpage_id]} #{row[:property]} #{row[:source_language]} source=#{row[:source_id]} status=#{row[:status]} items=#{row[:selected_count] || '?'}"
end
puts "Historical bilingual Title RDF identities: #{report[:paired_title_rdf_count]}"
puts report[:completeness]
if output
  abort "Refusing overwrite #{output}" if File.exist?(output)
  File.write(output, JSON.pretty_generate(report) + "\n")
  puts "Saved #{output} (local file only)"
end
