module Distillator
  class MigrationStatus
    CHECKS = [
      ["Fetch cache model present", -> { model_present? }],
      ["Native refresh regression", -> { test_file_present?("test/integration/distillator_refresh_rdf_uri_cache_test.rb") }],
      ["ResourceList validation", -> { test_file_present?("test/jobs/add_webpages_job_test.rb") }],
      ["DSL golden fixtures", -> { test_file_present?("test/services/dsl/distillator_golden_fixture_test.rb") }],
      ["Export invariance fixture", -> { test_file_present?("test/services/distillator/export_invariance_test.rb") }],
      ["Render-JS fallback coverage", -> { test_file_present?("test/integration/distillator_render_js_export_test.rb") }],
      ["JSON POST fallback coverage", -> { test_file_present?("test/integration/distillator_json_post_export_test.rb") }],
      ["Manual link export coverage", -> { test_file_present?("test/integration/distillator_manual_link_export_test.rb") }]
    ].freeze

    def self.call
      new.call
    end

    def call
      {
        checks: CHECKS.map { |label, fn| [label, fn.call] }.to_h,
        legacy_bypasses: known_legacy_bypasses
      }
    end

    private

    def self.model_present?
      defined?(Distillator::FetchCache).present?
    end

    def self.test_file_present?(path)
      Rails.root.join(path).exist?
    end

    def known_legacy_bypasses
      files = Dir[Rails.root.join("app/**/*.{rb}")].reject do |path|
        path.include?("/services/wringer_client.rb") || path.end_with?("app/services/distillator/migration_status.rb")
      end
      matches = files.select { |path| File.read(path).include?("WringerClient.fetch(") }
      { count: matches.count, files: matches.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }.sort }
    end
  end
end
