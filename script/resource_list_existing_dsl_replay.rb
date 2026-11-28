# frozen_string_literal: true

# Local-only QA replay. Executes the configured ResourceList Source DSL on
# SHA-verified HTML snapshots, without fetching or refreshing Statements.
# RAILS_ENV=development bundle exec ruby script/resource_list_existing_dsl_replay.rb PROBE_DIR SOURCE_ID
# WARNING: a trusted DSL may contain arbitrary Ruby; run only against a disposable
# local database, never against staging/production or untrusted Source code.
ENV["RAILS_ENV"] ||= "development"
require_relative "../config/environment"
require "digest"
require "json"

abort "Local development/test environment only" unless Rails.env.development? || Rails.env.test?
abort "Usage: ... resource_list_existing_dsl_replay.rb PROBE_DIR SOURCE_ID" unless ARGV.length == 2
require "webmock"
require_relative "../app/services/resource_lists/saved_dsl_replay"

WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: false)
source_id = Integer(ARGV.fetch(1), 10)
source = Source.includes(:property, :website).find(source_id)
abort "Use an enabled, selected ResourceList list Source" unless
  source.selected? && ["Webpage URL List", "URI List"].include?(source.property.label)
abort "Expected PostgreSQL read-only transaction protection" unless
  ActiveRecord::Base.connection.adapter_name.downcase.include?("postgresql")

folder = File.expand_path(ARGV.fetch(0))
runner = lambda do |algorithm:, url:, html:|
  executor = Dsl::Core::AlgorithmRunner.new(
    url:, render_js: source.render_js, scrape_options: {},
    tracer: Dsl::Tracing::NullTracer.new
  )
  executor.define_singleton_method(:fetch_result_for) do |url:, render_js:, scrape_options:, **|
    { status: :abort, body: ["abort_update", {
      error: "Saved-HTML DSL replay cannot fetch additional URLs",
      error_type: "SnapshotDslReplayFetchUnsupported",
      source: "saved_dsl_replay", step: "url"
    }], final_url: url, headers: {}, redirect_chain: [url], duration_ms: 0 }
  end
  executor.run(algorithm, snapshot_html: html)
end

result = nil
# Forbid DB writes by the DSL as well as ordinary network requests. A database
# transaction rollback is a second line of defense, not a Ruby sandbox.
ActiveRecord::Base.transaction do
  ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")
  result = ResourceLists::SavedDslReplay.call(directory: folder,
    algorithm: source.algorithm_value, run_dsl: runner)
  raise ActiveRecord::Rollback
end
report = {
  purpose: "offline_existing_source_dsl_replay",
  source_id:, website_id: source.website_id, property_label: source.property.label,
  algorithm_sha256: Digest::SHA256.hexdigest(source.algorithm_value.to_s),
  executed_on_saved_html: true, network_disabled: true, db_transaction_read_only: true,
  verified_completeness: false, extraction_parity_verified: false,
  status: result.status, errors: result.errors,
  terminal_page: result.terminal_page, total_values: result.total_values,
  duplicate_values: result.duplicate_values, pages: result.pages
}
out = File.join(folder, "dsl-snapshot-replay-source-#{source_id}.json")
File.binwrite(out, JSON.pretty_generate(report))
puts "status=#{report[:status]} source_id=#{source_id} terminal_page=#{result.terminal_page || '-'} " \
  "values=#{result.total_values} duplicates=#{result.duplicate_values || '-'} parity=UNVERIFIED"
puts "Saved #{out}"
exit(result.status == "dsl_replayed_parity_unverified" ? 0 : 2)
