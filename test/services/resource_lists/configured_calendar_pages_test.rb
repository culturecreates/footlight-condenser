require "test_helper"

module ResourceLists
  class ConfiguredCalendarPagesTest < ActiveSupport::TestCase
    self.fixture_table_names = []
    Page = Struct.new(:url)
    ROOT = "https://meridiancentrepointe.com"
    PATH = "/en/events"

    def pages(*suffixes)
      suffixes.map { |suffix| Page.new("#{ROOT}#{PATH}#{suffix}") }
    end

    test "Meridian zero-based pages 0 and 1 are accepted and ordered" do
      result = ConfiguredCalendarPages.call(webpages: pages("?page=1", "?page=0"), root: ROOT, path: PATH, first_page: 0)
      assert result.valid?, result.errors.inspect
      assert_equal [0, 1], result.pages.map(&:number)
    end

    test "missing zero-based first page blocks partial inventory" do
      result = ConfiguredCalendarPages.call(webpages: pages("?page=1"), root: ROOT, path: PATH, first_page: 0)
      refute result.valid?
      assert_includes result.errors, "Missing configured pagination page(s): 0"
    end

    test "zero-based root alias is not accepted implicitly" do
      result = ConfiguredCalendarPages.call(webpages: pages("", "?page=0"), root: ROOT, path: PATH, first_page: 0)
      refute result.valid?
      assert result.errors.any? { |error| error.include?("Unrecognized or ambiguous") }
    end

    test "duplicate page zero and calendar filters are rejected" do
      result = ConfiguredCalendarPages.call(webpages: pages("?page=0", "?page=0", "?page=1&genre=music"),
        root: ROOT, path: PATH, first_page: 0)
      refute result.valid?
      assert result.errors.any? { |error| error.include?("Duplicate calendar page 0") }
      assert result.errors.any? { |error| error.include?("Unrecognized or ambiguous") }
    end

    test "one-based default is unchanged" do
      result = ConfiguredCalendarPages.call(webpages: pages("", "?page=2"), root: ROOT, path: PATH)
      assert result.valid?, result.errors.inspect
      assert_equal [1, 2], result.pages.map(&:number)
      rejected = ConfiguredCalendarPages.call(webpages: pages("?page=0", "?page=1"), root: ROOT, path: PATH)
      refute rejected.valid?
      assert rejected.errors.any? { |error| error.include?("outside the allowed range 1..25") }
    end

    test "missing interior page, leading zero and fragment fail closed" do
      missing = ConfiguredCalendarPages.call(webpages: pages("?page=0", "?page=2"), root: ROOT, path: PATH, first_page: 0)
      refute missing.valid?
      assert_includes missing.errors, "Missing configured pagination page(s): 1"
      ["?page=00", "?page=1#anchor"].each do |bad|
        refute ConfiguredCalendarPages.call(webpages: pages("?page=0", bad), root: ROOT, path: PATH, first_page: 0).valid?
      end
    end
  end
end
