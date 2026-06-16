require "test_helper"

module Statements
  class RefreshWebpageStatementsServiceTest < ActiveSupport::TestCase
    class DummyRefreshHelper
      attr_reader :calls

      def initialize
        @calls = []
      end

      def refresh_statement_helper(stat, scrape_options)
        @calls << { statement_id: stat.id, scrape_options: scrape_options }
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

    test "call updates existing statement cache through the real refresh helper" do
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
        render_js: false,
        property: properties(:four),
        website: website
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
      Distillator::NativeFetch.expects(:call).once.returns(
        status: :ok,
        body: "<html><body><h1>Service Refreshed Title</h1></body></html>",
        raw_body: "<html><body><h1>Service Refreshed Title</h1></body></html>",
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
        scrape_options: { force_scrape_every_hrs: "0" }
      )

      assert_equal [], result
      assert_equal "Service Refreshed Title", statement.reload.cache
    ensure
      ENV["DISTILLATOR_FETCH_MODE"] = previous_mode
    end
  end
end
