# frozen_string_literal: true

# QA-only, saved-input bilingual ResourceList refresh.
#
# DATABASE_URL=postgresql:///footlight_condenser_dansedanse_qa \
# DANSE_EN_HTML=/tmp/danse-en-1.html DANSE_FR_HTML=/tmp/danse-fr-1.html \
# bin/rails runner script/danse_danse_keyed_qa_refresh.rb /tmp/danse-danse-keyed-trial.json
#
# Append --apply to persist *only* the QA-copy ResourceList statement caches,
# after preflight and baseline comparison. Do not use this script in production.
require "json"

manifest_path, action = ARGV
abort "Usage: rails runner script/danse_danse_keyed_qa_refresh.rb MANIFEST.json [--apply]" unless
  manifest_path && (action.nil? || action == "--apply")

db = ActiveRecord::Base.connection_db_config.database
abort "Wrong database: #{db}" unless db == "footlight_condenser_dansedanse_qa"
abort "Refusing production environment" if Rails.env.production?

website = Website.find_by!(seedurl: "dansedansetest-ca")
input_paths = {
  "en" => ENV.fetch("DANSE_EN_HTML") { abort "Missing DANSE_EN_HTML" },
  "fr" => ENV.fetch("DANSE_FR_HTML") { abort "Missing DANSE_FR_HTML" }
}
html_pages = input_paths.transform_values do |csv|
  paths = csv.split(",").map(&:strip)
  abort "Empty calendar page path" if paths.empty? || paths.any?(&:empty?)
  paths.map { |path| File.read(path) }
end
manifest = JSON.parse(File.read(manifest_path))
result = ResourceLists::DanseDanseKeyedQaRefresh.call(website: website,
  html_pages: html_pages, expected_manifest: manifest, apply: action == "--apply")
puts "#{result.status.upcase}: #{result.pair_count} bilingual pairs, digest=#{result.digest}"
puts "Created webpages: #{result.imported_ids.size}"
