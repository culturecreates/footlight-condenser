# frozen_string_literal: true

require "test_helper"
require "json"
require "fileutils"
require_relative "../support/jsonld_comparator"

class ExportArtsdataIntegrationTest < ActiveSupport::TestCase
  include JsonldComparator

  BASELINE_DIR = Rails.root.join("data/migration_baseline")
  SOURCE_FILE = Rails.root.join("test/services/export_artsdata_integration_test.rb")

  #
  # --- HELPERS ---
  #

  def export_debug?
    ENV["EXPORT_DEBUG"].present?
  end

  def debug_export(message)
    return unless export_debug?

    puts("[EXPORT_DEBUG] #{message}")
  end

  def assert_publishable_present!(seedurl:, publishable_events:, source:)
    debug_export("source=#{source} seedurl=#{seedurl} publishable_events_count=#{publishable_events.size}")
    assert_operator(
      publishable_events.size,
      :>,
      0,
      "publishable_events empty before export (source=#{source}, seedurl=#{seedurl})"
    )
  end

  def run_export(seedurl:)
    # Calls the same logic as your rake task
    controller = GraphsController.new
    controller.params = ActionController::Parameters.new(seedurl: seedurl)
    controller.website

    publishable_events = controller.instance_variable_get(:@publishable) || []
    assert_publishable_present!(seedurl: seedurl, publishable_events: publishable_events, source: "graphs_controller.website")

    controller.instance_variable_get(:@dump)
  end

  def run_export_old(seedurl:)
    publishable = EventsController.new.publishable_events(seedurl)
    assert_publishable_present!(seedurl: seedurl, publishable_events: publishable, source: "dump_events_old")
    JsonldGenerator.dump_events_old(publishable)
  end

  def run_export_new(seedurl:)
    publishable = EventsController.new.publishable_events(seedurl)
    assert_publishable_present!(seedurl: seedurl, publishable_events: publishable, source: "dump_events")
    JsonldGenerator.dump_events(publishable)
  end

  def export_cases
    source = File.read(SOURCE_FILE)
    source
      .scan(/with_replay\("([^"]+)"\)\s+do\s+output\s*=\s*run_export\(seedurl:\s*"([^"]+)"\)/m)
      .map { |replay, seedurl| { seedurl: seedurl, replay: replay } }
      .uniq
  end

  def write_diff(seedurl:, old_output:, new_output:)
    output_dir = Rails.root.join("tmp")
    FileUtils.mkdir_p(output_dir)

    safe_seedurl = seedurl.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
    safe_seedurl = "site" if safe_seedurl.blank?

    path = output_dir.join("diff_#{safe_seedurl}.json")
    payload = {
      seedurl: seedurl,
      old: JSON.parse(old_output),
      new: JSON.parse(new_output)
    }
    File.write(path, JSON.pretty_generate(payload))
    path
  end

  def load_baseline(file)
    path = BASELINE_DIR.join(file)
    raise "Missing baseline file: #{file}" unless File.exist?(path)

    JSON.parse(File.read(path))
  end

  def with_replay(site)
    old_replay = ENV["REPLAY_FETCH"]
    old_site = ENV["FETCH_SITE"]

    ENV["REPLAY_FETCH"] = "true"
    ENV["FETCH_SITE"] = site

    yield
  ensure
    ENV["REPLAY_FETCH"] = old_replay
    ENV["FETCH_SITE"] = old_site
  end

  #
  # --- TESTS ---
  #

  # test "culture3r matches baseline" do
  #   with_replay("culture3r_com") do
  #     output = run_export(seedurl: "culture3r-com")
  #     baseline = load_baseline("culture3r_com.jsonld")

  #     assert_jsonld_equal baseline, output
  #   end
  # end

  # # Uncomment progressively once first test is stable

  # test "co_motion matches baseline" do
  #   with_replay("co_motion_ca") do
  #     output = run_export(seedurl: "co-motion-ca")
  #     baseline = load_baseline("co_motion_ca.jsonld")

  #     assert_jsonld_equal baseline, output
  #   end
  # end

  # test "culturemauricie matches baseline" do
  #   with_replay("culturemauricie_lepointdevente_com") do
  #     output = run_export(seedurl: "culturemauricie_lepointdevente-com")
  #     baseline = load_baseline("culturemauricie_lepointdevente_com.jsonld")

  #     assert_jsonld_equal baseline, output
  #   end
  # end

  # test "gatineau matches baseline" do
  #   with_replay("gatineau_cloud") do
  #     output = run_export(seedurl: "gatineau-cloud")
  #     baseline = load_baseline("gatineau_cloud.jsonld")

  #     assert_jsonld_equal baseline, output
  #   end
  # end

  # test "maisondelaculture matches baseline" do
  #   with_replay("maisondelaculture_ca") do
  #     output = run_export(seedurl: "maisondelaculture-ca")
  #     baseline = load_baseline("maisondelaculture_ca.jsonld")

  #     assert_jsonld_equal baseline, output
  #   end
  # end

  # test "ptitbonheur matches baseline" do
  #   with_replay("ptitbonheur_org") do
  #     output = run_export(seedurl: "ptitbonheur-org")
  #     baseline = load_baseline("ptitbonheur_org.jsonld")

  #     assert_jsonld_equal baseline, output
  #   end
  # end

  # test "optimized dump matches legacy dump for all configured replay cases" do
  #   cases = export_cases
  #   assert_operator cases.size, :>, 0

  #   cases.each do |test_case|
  #     with_replay(test_case[:replay]) do
  #       old_output = run_export_old(seedurl: test_case[:seedurl])
  #       new_output = run_export_new(seedurl: test_case[:seedurl])

  #       begin
  #         assert_jsonld_equal JSON.parse(old_output), JSON.parse(new_output)
  #       rescue Minitest::Assertion => e
  #         diff_path = write_diff(
  #           seedurl: test_case[:seedurl],
  #           old_output: old_output,
  #           new_output: new_output
  #         )
  #         raise Minitest::Assertion, "#{e.message}\nDiff written: #{diff_path}"
  #       end
  #     end
  #   end
  # end
end
