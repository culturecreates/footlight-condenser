require "test_helper"

module Statements
  class RefreshWebpageStatementsServiceTest < ActiveSupport::TestCase
    class DummyRefreshHelper
      attr_reader :calls

      def initialize
        @calls = []
      end

      def refresh_statement_helper(stat, scrape_options)
        @calls << { statement_id: stat.id, scrape_options: scrape_options.except(:page_fetch) }
        { saved: false }
      end
    end

    test "call delegates statement refreshes to provided helper and returns error list" do
      webpage = webpages(:six)
      helper = DummyRefreshHelper.new
      service = Statements::RefreshWebpageStatementsService.new(refresh_helper: helper)

      result = service.call(webpage: webpage, default_language: "en", scrape_options: { force_scrape_every_hrs: 1 })

      assert_kind_of Array, result
      assert_operator helper.calls.size, :>, 0
      assert_equal({ force_scrape_every_hrs: 1 }, helper.calls.first[:scrape_options])
    end

    test "call preserves string force_scrape_every_hrs through helper refreshes" do
      webpage = webpages(:six)
      helper = DummyRefreshHelper.new
      service = Statements::RefreshWebpageStatementsService.new(refresh_helper: helper)

      service.call(webpage: webpage, default_language: "en", scrape_options: { force_scrape_every_hrs: "1" })

      assert_operator helper.calls.size, :>, 0
      assert_equal({ force_scrape_every_hrs: "1" }, helper.calls.first[:scrape_options])
    end

    test "call refreshes the existing statement for matching webpage and source" do
      webpage = webpages(:culture3r_refresh_fixture)
      statement = statements(:culture3r_refresh_statement)
      helper = DummyRefreshHelper.new
      service = Statements::RefreshWebpageStatementsService.new(refresh_helper: helper)

      service.call(webpage: webpage, default_language: "en", scrape_options: { force_scrape_every_hrs: "1" })

      matching_call = helper.calls.find { |call| call[:statement_id] == statement.id }

      assert matching_call, "expected existing statement #{statement.id} to be refreshed"
      assert_equal({ force_scrape_every_hrs: "1" }, matching_call[:scrape_options])
      assert_equal statement.id, Statement.find_by!(webpage_id: webpage.id, source_id: statement.source_id).id
    end

    test "three ResourceList refreshes import changed URLs with review status intact" do
      website = websites(:one)
      resource_list = RdfsClass.create!(name: "ResourceList")
      webpage = website.webpages.create!(url: "https://fixtures.example/calendar", rdf_uri: "adr:refresh-calendar",
        rdfs_class: resource_list, language: "en")
      algorithms = {
        AddWebpagesJob::RDF_CLASS_LABEL => "manual=Event",
        AddWebpagesJob::URI_LIST_LABEL => "xpath=//li/@data-uri",
        AddWebpagesJob::WEBPAGE_URL_LIST_LABEL => "xpath=//li/@data-url"
      }
      sources = algorithms.to_h do |label, algorithm|
        property = Property.create!(rdfs_class: resource_list, label: label, uri: "urn:refresh:#{label.parameterize}")
        [label, website.sources.create!(property: property, language: "en", selected: true, algorithm_value: algorithm)]
      end

      fixed = webpage.statements.create!(source: sources.fetch(AddWebpagesJob::RDF_CLASS_LABEL), manual: true,
        selected_individual: true, cache: "Event", status: "initial", status_origin: "condenser_refresh")
      fixed_before = fixed.reload.attributes
      helper = Object.new.extend(StatementsHelper)
      helper.stubs(:trace_enabled_for_request?).returns(false)
      service = Statements::RefreshWebpageStatementsService.new(refresh_helper: helper)

      first_refresh = 1.second.from_now.change(usec: 0)
      3.times do |index|
        travel_to first_refresh + index.hours do
          url = "https://fixtures.example/event/#{index}"
          uri = "adr:scheduled-event-#{index}"
          helper.expects(:run_dsl).with(has_entries(algorithm: algorithms.fetch(AddWebpagesJob::URI_LIST_LABEL))).returns([[uri].to_json])
          helper.expects(:run_dsl).with(has_entries(algorithm: algorithms.fetch(AddWebpagesJob::WEBPAGE_URL_LIST_LABEL))).returns([[url].to_json])

          assert_empty service.call(webpage: webpage, default_language: "en", scrape_options: { force_scrape: true })
          assert_difference("Webpage.count", 1) { AddWebpagesJob.perform_now(webpage.id, refresh_new: false) }
          assert_equal uri, website.webpages.find_by!(url: url).rdf_uri
          [AddWebpagesJob::URI_LIST_LABEL, AddWebpagesJob::WEBPAGE_URL_LIST_LABEL].each do |label|
            refreshed = webpage.statements.find_by!(source: sources.fetch(label))
            assert_equal "updated", refreshed.status
            assert_equal Time.current, refreshed.cache_refreshed
            assert_not refreshed.manual?
          end
        end
      end
      assert_equal fixed_before, fixed.reload.attributes
    end

    test "new fixed source values follow source edits without setting a manual override" do
      website = websites(:one)
      resource_list = RdfsClass.create!(name: "ResourceList")
      webpage = website.webpages.create!(url: "https://fixtures.example/fixed", rdf_uri: "adr:fixed-calendar",
        rdfs_class: resource_list, language: "en")
      property = Property.create!(rdfs_class: resource_list, label: AddWebpagesJob::RDF_CLASS_LABEL, uri: "urn:refresh:fixed")
      source = website.sources.create!(property: property, language: "en", selected: true, algorithm_value: "manual=Event")
      service = Statements::RefreshWebpageStatementsService.new

      assert_empty service.call(webpage: webpage, default_language: "en")
      value = webpage.statements.find_by!(source: source)
      assert_equal "Event", value.cache
      assert_not value.manual?
      source.update!(algorithm_value: "manual=None")

      assert_empty service.call(webpage: webpage, default_language: "en")
      assert_equal "None", value.reload.cache
    end

    test "a failed source refresh does not auto-review an initial statement" do
      webpage = webpages(:culture3r_refresh_fixture)
      statement = statements(:culture3r_refresh_statement)
      statement.source.update!(auto_review: true)
      statement.update_columns(status: "initial")
      helper = DummyRefreshHelper.new

      Statements::RefreshWebpageStatementsService.new(refresh_helper: helper).call(webpage: webpage, default_language: "en")

      assert_includes helper.calls.map { |call| call[:statement_id] }, statement.id
      assert_equal "initial", statement.reload.status
    end

    %w[legacy shadow active].each do |mode|
      %w[ok updated].each do |status|
        test "#{mode} refresh preserves #{status} reviewed performers while refreshing automatic statements" do
          website = Website.create!(
            name: "Reviewed performers #{mode} #{status}",
            seedurl: "reviewed-performers-#{mode}-#{status}",
            default_language: "fr",
            distillator_mode: mode
          )
          webpage = Webpage.create!(
            website: website,
            rdfs_class: rdfs_classes(:one),
            url: "https://fixtures.example/#{website.seedurl}/event",
            rdf_uri: "footlight:#{website.seedurl}",
            language: "fr"
          )

          # Production replay cases: a fresh lookup can lose OSM or add an
          # incorrect Theatre Denise-Pelletier match to Patrick Watson.
          # Ordinary refresh must retain the operator's reviewed relationships.
          reviewed = [
            ["OSM", "http://kg.artsdata.ca/resource/K10-555"],
            ["Patrick Watson", "http://kg.artsdata.ca/resource/K12-450"]
          ].map do |name, uri|
            source = Source.create!(
              website: website, property: properties(:nine), language: "fr",
              selected: true, selected_by: "test", algorithm_value: "xpath=//h1/text()"
            )
            statement = Statement.create!(
              webpage: webpage, source: source, manual: true,
              selected_individual: true, status: "initial",
              cache: [name, "Organization", [name, uri]].to_json
            )
            statement.update_columns(
              status: status, status_origin: "operator_review",
              cache_refreshed: 2.days.ago, cache_changed: 3.days.ago
            )
            statement
          end
          before = reviewed.to_h { |statement| [statement.id, statement.reload.attributes] }

          automatic_source = Source.create!(
            website: website, property: properties(:four), language: "fr",
            selected: true, selected_by: "test", algorithm_value: "xpath=//h1/text()"
          )
          automatic = Statement.create!(
            webpage: webpage, source: automatic_source, manual: false,
            selected_individual: true, status: "initial", cache: "Automatic title"
          )
          helper = DummyRefreshHelper.new
          result = Statements::RefreshWebpageStatementsService.new(refresh_helper: helper).call(
            webpage: webpage, default_language: "fr", scrape_options: { force_scrape_every_hrs: "0" }
          )

          assert_equal [], result
          assert_equal [automatic.id], helper.calls.map { |call| call[:statement_id] }
          reviewed.each do |statement|
            assert_equal before.fetch(statement.id), statement.reload.attributes,
              "Reviewed performer, selection, audit metadata and timestamps must remain unchanged"
          end
        end
      end
    end

    {
      "plain" => [false, false, false],
      "rendered" => [true, true, true],
      "mixed" => [false, true, true]
    }.each do |label, (title_render_js, description_render_js, render_js)|
      test "#{label} sources share one page fetch during forced refresh" do
        previous_mode = ENV["DISTILLATOR_FETCH_MODE"]
        ENV["DISTILLATOR_FETCH_MODE"] = "internal"
        Distillator::FetchCache.delete_all

        website = Website.create!(
          name: "Service Refresh Fixture",
          seedurl: "service-refresh-fixture",
          graph_name: "https://fixtures.example/service-refresh",
          default_language: "en",
          distillator_mode: "active"
        )
        webpage = Webpage.create!(
          website: website,
          rdfs_class: rdfs_classes(:one),
          url: "https://fixtures.example/service-refresh/event",
          rdf_uri: "footlight:service-refresh-event",
          language: "en"
        )
        source = Source.create!(
          algorithm_value: "xpath=//h1/text()",
          selected: true,
          selected_by: "test",
          language: "en",
          render_js: title_render_js,
          property: properties(:four),
          website: website
        )
        description_source = website.sources.create!(
          algorithm_value: "url=$url;xpath=//p/text()",
          selected: true, language: "en", render_js: description_render_js, property: properties(:five)
        )
        statement = Statement.create!(
          cache: "Old Service Title",
          status: "initial",
          status_origin: "test",
          cache_refreshed: 1.day.ago,
          cache_changed: 1.day.ago,
          source: source,
          webpage: webpage,
          selected_individual: true
        )

        Distillator::FetchGuard.stubs(:check_url).returns(Distillator::FetchGuard::Result.new(allowed: true))
        Distillator::FetchGuard.stubs(:check_response).returns(Distillator::FetchGuard::Result.new(allowed: true))
        Distillator::NativeFetch.expects(:call).with(has_entries(url: webpage.url, render_js: render_js)).once.returns(
          status: :ok,
          body: "<html><body><h1>Service Refreshed Title</h1><p>Shared description</p></body></html>",
          raw_body: "<html><body><h1>Service Refreshed Title</h1><p>Shared description</p></body></html>",
          headers: { content_type: "text/html" },
          final_url: webpage.url,
          redirect_chain: [webpage.url],
          wringer: { signals: {}, hints: [] },
          http_code: 200
        )

        helper = Object.new
        helper.extend(StatementsHelper)
        helper.instance_variable_set(:@_statement_refresh_cookies, {})
        helper.define_singleton_method(:cookies) { @_statement_refresh_cookies }

        result = Statements::RefreshWebpageStatementsService.new(refresh_helper: helper).call(
          webpage: webpage,
          default_language: "en",
          scrape_options: { force_scrape: true }
        )

        assert_equal [], result
        assert_equal "Service Refreshed Title", statement.reload.cache
        assert_equal "Shared description", webpage.statements.find_by!(source: description_source).cache
        if label == "mixed"
          single_refresh = helper.refresh_statement_helper(statement)
          assert_empty single_refresh[:errors]
          assert_equal "Service Refreshed Title", statement.reload.cache
        end
      ensure
        ENV["DISTILLATOR_FETCH_MODE"] = previous_mode
      end
    end
  end
end
