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
  end
end
