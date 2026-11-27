require "test_helper"

module ResourceLists
  class DanseDanseKeyedQaRefreshTest < ActiveSupport::TestCase
    FakeWebsite = Struct.new(:id, :seedurl, :test_copy_of_website) do
      def persisted? = true
    end

    test "get_sorted_calendars rejects missing or unauthorized shared context" do
      runner = Dsl::Core::AlgorithmRunner.new(
        url: "https://www.dansedanse.ca/en/shows", render_js: false, scrape_options: {},
        tracer: Dsl::Tracing::NullTracer.new
      )
      result = runner.run("get_sorted_calendars=urls,en")
      assert_equal "abort_update", result.first
      assert_equal "KeyedCalendarContextError", result.last[:error_type]
    end

    test "get_sorted_calendars exposes matching ordered arrays only from validated QA context" do
      source = FakeWebsite.new(1, "dansedanse-ca", nil)
      copy = FakeWebsite.new(2, "dansedansetest-ca", source)
      values = {
        "en" => { "urls" => ["https://www.dansedanse.ca/en/shows/b", "https://www.dansedanse.ca/en/shows/a"],
          "uris" => %w[urn:qa:b urn:qa:a] },
        "fr" => { "urls" => ["https://www.dansedanse.ca/fr/spectacles/b", "https://www.dansedanse.ca/fr/spectacles/a"],
          "uris" => %w[urn:qa:b urn:qa:a] }
      }
      context = DanseDanseKeyedQaRefresh::Context.new(website_id: 2, values: values)
      runner = ->(code) {
        Dsl::Core::AlgorithmRunner.new(
          url: "https://www.dansedanse.ca/en/shows", render_js: false,
          scrape_options: { website: copy, keyed_calendar_context: context },
          tracer: Dsl::Tracing::NullTracer.new
        ).run("get_sorted_calendars=#{code}")
      }
      assert_equal values["en"]["urls"], runner.call("urls,en")
      assert_equal values["fr"]["uris"], runner.call("uris,fr")
      assert_equal ["abort_update", {
        error: "Invalid calendar language", error_type: "Invalid", source: "dsl_runner",
        step: "get_sorted_calendars"
      }], runner.call("urls,de")
      assert_equal values["fr"]["urls"], runner.call("urls,fr")
    end

    test "shared context cannot be used by another website" do
      source = FakeWebsite.new(1, "dansedanse-ca", nil)
      copy = FakeWebsite.new(2, "dansedansetest-ca", source)
      context = DanseDanseKeyedQaRefresh::Context.new(website_id: 2,
        values: { "en" => { "urls" => [], "uris" => [] }, "fr" => { "urls" => [], "uris" => [] } })
      copy.id = 3
      runner = Dsl::Core::AlgorithmRunner.new(
        url: "https://www.dansedanse.ca/en/shows", render_js: false,
        scrape_options: { website: copy, keyed_calendar_context: context },
        tracer: Dsl::Tracing::NullTracer.new
      )
      result = runner.run("get_sorted_calendars=urls,en")
      assert_equal "abort_update", result.first
      assert_equal "KeyedCalendarContextError", result.last[:error_type]
    end

    test "failed read-only preflight does not modify resources" do
      site = Website.new(seedurl: "dansedanse-ca")
      error = assert_raises(DanseDanseKeyedQaRefresh::Invalid) do
        DanseDanseKeyedQaRefresh.call(website: site, html_pages: {}, expected_manifest: {}, apply: false)
      end
      assert_match(/QA copy/, error.message)
    end
  end
end
