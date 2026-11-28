require "test_helper"

module Websites
  class CreateTestCopyTest < ActiveSupport::TestCase
    # Build the small related dataset through ActiveRecord under real FK checks.
    self.fixture_table_names = []

    setup do
      @original = Website.create!(name: "Danse Danse", seedurl: "dansedanse-ca",
        graph_name: "https://example.org/dansedanse", default_language: "fr",
        monitorable: true, schedule_every_days: 1, last_refresh: 1.day.ago,
        schedule_time: Time.zone.parse("00:05"))
      @event_class = RdfsClass.find_or_create_by!(name: "Event")
      @property = Property.create!(rdfs_class: @event_class, label: "QA title", uri: "urn:qa:title")
      @source = @original.sources.create!(property: @property, language: "fr", selected: true,
        algorithm_value: "xpath=//h1/text()", selected_by: "test", render_js: false)
      @original_uri = "http://kg.footlight.io/resource/dansedanse-ca_event-a"
      @fr = @original.webpages.create!(url: "https://www.dansedanse.ca/fr/spectacles/event-a",
        rdf_uri: @original_uri, rdfs_class: @event_class, language: "fr")
      @en = @original.webpages.create!(url: "https://www.dansedanse.ca/en/shows/event-a",
        rdf_uri: @original_uri, rdfs_class: @event_class, language: "en")
      @record = @fr.statements.create!(source: @source, selected_individual: true,
        status: "ok", cache: "Danse", manual: true)
    end

    test "copy suggests seedurl and retains bilingual pairing with new RDF identity" do
      assert_equal "dansedansetest-ca", CreateTestCopy.suggest_seedurl(@original.seedurl)
      result = nil
      assert_difference("Website.count", 1) { result = CreateTestCopy.call(source: @original) }
      copy = result.website
      assert_equal @original.id, copy.test_copy_of_website_id
      assert_equal [@en.url, @fr.url].sort, copy.webpages.pluck(:url).sort
      assert_equal 1, copy.webpages.distinct.count(:rdf_uri)
      assert_not_equal @original_uri, copy.webpages.first.rdf_uri
      assert_includes copy.webpages.first.rdf_uri, "dansedansetest-ca_"
      assert_equal [@original_uri], @original.webpages.distinct.pluck(:rdf_uri)
      assert_equal "Danse", Statement.find_by!(webpage_id: result.webpage_map.fetch(@fr.id),
        source_id: result.source_map.fetch(@source.id)).cache
      assert_equal false, copy.refresh_scheduled?
      assert_nil copy.schedule_every_days
      assert_equal false, copy.monitorable
      assert_equal "shadow", copy.distillator_mode
      assert_raises(ArgumentError) { ExportGraphToDatabus.export_events(copy.seedurl, "https://example.org") }
    end

    test "clone preserves selected and manual flags but uses new Source and Webpage IDs" do
      result = CreateTestCopy.call(source: @original)
      copied = Statement.find_by!(source_id: result.source_map.fetch(@source.id), webpage_id: result.webpage_map.fetch(@fr.id))
      assert copied.selected_individual
      assert copied.manual
      assert_equal @record.status, copied.status
      refute_equal @record.source_id, copied.source_id
      refute_equal @record.webpage_id, copied.webpage_id
      assert_equal @original.webpages.count, result.website.webpages.count
      assert_equal @original.sources.count, result.website.sources.count
    end

    test "clone remaps RDF URI values in JSON statement payloads without changing public links" do
      @record.update_columns(cache: [@original_uri, "https://www.dansedanse.ca/en/shows/event-a"].to_json)
      result = CreateTestCopy.call(source: @original)
      copied = Statement.find_by!(source_id: result.source_map.fetch(@source.id),
        webpage_id: result.webpage_map.fetch(@fr.id))
      assert_equal [result.rdf_uri_map.fetch(@original_uri), @en.url], JSON.parse(copied.cache)
      assert_equal [@original_uri, @en.url], JSON.parse(@record.reload.cache)
    end

    test "duplicate seedurl rolls back and never changes the original" do
      CreateTestCopy.call(source: @original)
      count = Website.count
      assert_raises(CreateTestCopy::InvalidCopy) { CreateTestCopy.call(source: @original) }
      assert_equal count, Website.count
      assert_equal 2, @original.webpages.count
    end

    test "cross-site ResourceList discovery target blocks an unsafe copy" do
      list_class = RdfsClass.find_or_create_by!(name: "ResourceList")
      @original.webpages.create!(url: "https://www.dansedanse.ca/fr/spectacles",
        rdf_uri: "rdf:dansedanse-ca:resource-list", rdfs_class: list_class,
        language: "fr", discovery_target_website: Website.create!(name: "Outside", seedurl: "outside-ca"))
      assert_no_difference("Website.count") do
        error = assert_raises(CreateTestCopy::InvalidCopy) { CreateTestCopy.call(source: @original) }
        assert_match(/Cross-site ResourceList/, error.message)
      end
    end
  end
end
