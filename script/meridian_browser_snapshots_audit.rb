# frozen_string_literal: true

# Read-only offline comparison of four previously saved browser documents.
# The --page values are *actual request query parameters*, not visible pager
# labels or local filenames. No network requests and no DB mutations.
require "json"
require "optparse"

module MeridianBrowserSnapshotsAudit
  module_function

  def run(captures:, output: nil, language: "fr")
    raise "Production prohibited" if Rails.env.production?
    conn = ActiveRecord::Base.connection
    raise "Refusing unknown DB" unless conn.current_database.match?(/\Afootlight_condenser_[a-z0-9_]+\z/)
    raise "Refusing overwrite: #{output}" if output && File.exist?(output)
    raise "Provide at least two --page captures" unless captures.size.between?(2, 25)

    report = nil
    conn.transaction do
      conn.execute("SET TRANSACTION READ ONLY")
      original = Website.find_by!(seedurl: "meridiancentrepointe-com")
      qa = if conn.column_exists?(:websites, :test_copy_of_website_id)
        Website.where(test_copy_of_website_id: original.id).sole
      else
        raise "QA copy relationship migration is absent from this database"
      end
      raise "Expected unscheduled QA copy" unless qa.distillator_mode == "shadow" && !qa.refresh_scheduled?
      path = ResourceLists::MeridianSavedPagesComparison::PATHS.fetch(language)
      root_url = ResourceLists::MeridianSavedPagesComparison::ROOT + path
      list_class = RdfsClass.find_by!(name: "ResourceList")
      list = qa.webpages.where(url: root_url, language: language, rdfs_class_id: list_class.id).sole
      selected = list.statements.joins(source: :property)
        .where(selected_individual: true, sources: { selected: true, website_id: qa.id },
          properties: { label: "Webpage URL List" }).includes(:source).sole
      source = selected.source
      steps = source.algorithm_value.to_s.split(";").map { |step| step.strip.partition("=") }
      xpaths = steps.filter_map { |kind, separator, value| value if kind == "xpath" && separator == "=" }
      raise "Expected one selected URL XPath" unless xpaths.one?
      input = captures.map do |capture|
        file = capture.fetch(:path)
        raise "Missing file: #{file}" unless File.file?(file)
        raise "Empty or oversized file: #{file}" unless File.size(file).between?(1, ResourceLists::MeridianSavedPagesComparison::MAX_BYTES)
        capture.slice(:label, :page).merge(html: File.binread(file))
      end
      report = ResourceLists::MeridianSavedPagesComparison.call(snapshots: input, xpath: xpaths.first, language: language)
      report[:database] = conn.current_database
      report[:qa_site] = { website_id: qa.id, seedurl: qa.seedurl,
        source_id: source.id, source_algorithm_sha256: Digest::SHA256.hexdigest(source.algorithm_value.to_s) }
      report[:captures] = captures
    end

    report[:snapshots].each do |row|
      puts "#{row[:label]} page=#{row[:requested_page]} state=#{row[:state]} xpath=#{row[:xpath_hits]} unique=#{row[:distinct_event_count]} hash=#{row[:sha256][0, 12]} pager=#{row[:pager].inspect}"
    end
    report[:same_url_comparisons].each do |comparison|
      puts "SAME-URL #{comparison[:page]} #{comparison[:first]}/#{comparison[:second]} same=#{comparison[:same_event_urls]} only_first=#{comparison[:first_only].length} only_second=#{comparison[:second_only].length}"
    end
    puts "Page content unstable at: #{report[:unstable_page_numbers].inspect}"
    puts report[:completeness]
    if output
      File.write(output, JSON.pretty_generate(report) + "\n")
      puts "Saved #{output}"
    end
    report
  end
end

captures = []
output = nil
language = "fr"
OptionParser.new do |parser|
  parser.on("--page LABEL:NUMBER:PATH", "Browser capture associated with a specific ?page=NUMBER URL") do |spec|
    label, number, path = spec.split(":", 3)
    abort "Invalid --page #{spec}" unless label.present? && number.to_s.match?(/\A(?:0|[1-9]\d*)\z/) &&
      number.to_i < ResourceLists::MeridianPager::MAX_PAGES && path.present? && captures.none? { |row| row[:label] == label }
    captures << { label: label, page: number.to_i, path: path }
  end
  parser.on("--language LANG", "en or fr") { |value| language = value }
  parser.on("--json PATH") { |value| output = value }
end.parse!(ARGV)
abort "Unexpected args" unless ARGV.empty?
MeridianBrowserSnapshotsAudit.run(captures: captures, output: output, language: language)
