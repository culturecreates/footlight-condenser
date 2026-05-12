require "fileutils"

namespace :export do
  desc "Export Artsdata JSON-LD baseline for a website (usage: rake export:artsdata seedurl=example.com)"
  task artsdata: :environment do
    seedurl = ENV["seedurl"] || ENV["SEEDURL"]
    raise ArgumentError, "Missing seedurl. Usage: rake export:artsdata seedurl=example.com" if seedurl.blank?

    started_at = Time.current if ENV["EXPORT_ARTSDATA_TIMING"].present?
    dump = ExportArtsdataService.call(seedurl: seedurl)
    puts "Export generation: #{(Time.current - started_at).round(3)}s" if started_at

    sanitized_site = seedurl.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    sanitized_site = "site" if sanitized_site.blank?

    output_dir = Rails.root.join("data", "migration_baseline")
    FileUtils.mkdir_p(output_dir)
    output_path = output_dir.join("#{sanitized_site}.jsonld")
    File.write(output_path, dump)

    puts "Wrote #{output_path}"
  end
end
