require "test_helper"

module ResourceLists
  class PaginationTest < ActiveSupport::TestCase
    Page = Struct.new(:id, :url, :website_id, :discovery_target_website_id, :language, :rdf_uri, keyword_init: true)

    test "shared URI and distinct URI pages accept a trailing empty tail" do
      [true, false].each do |shared_uri|
        pages = pages_for(%w[/events /events/page/1 /events/page/2 /events/page/3], shared_uri: shared_uri)
        evidence = rows_for([20, 12, 0, 0])
        Pagination.review!(pages, evidence)
        assert_equal %w[event event event event], evidence.map { |row| row[:status] }
        assert_equal [true, true], evidence.last(2).map { |row| row.dig(:pagination, :trailing_empty) }
      end
    end

    test "empty second page after a nonempty first page is healthy" do
      evidence = rows_for([18, 0])
      Pagination.review!(pages_for(%w[/events /events/page/1]), evidence)
      assert_equal %w[event event], evidence.map { |row| row[:status] }
    end

    test "internal pagination gaps require review rather than silently passing" do
      evidence = rows_for([20, 0, 5, 0])
      Pagination.review!(pages_for(%w[/events /events/page/1 /events/page/2 /events/page/3]), evidence)
      assert_equal "unverified", evidence[1][:status]
      assert_equal "pagination_gap", evidence[1][:reason]
      assert_equal "event", evidence[3][:status]
    end

    test "independent paths are not grouped and failed extraction is preserved" do
      evidence = rows_for([0, 20])
      Pagination.review!(pages_for(%w[/events/list /events/archive]), evidence)
      assert_equal %w[event event], evidence.map { |row| row[:status] }
      assert_nil evidence.first[:pagination]

      evidence.last.merge!(status: "unverified", reason: "extraction_failed")
      Pagination.review!(pages_for(%w[/events /events/page/1]), evidence)
      assert_equal "extraction_failed", evidence.last[:reason]
    end

    test "page query parameter is recognized" do
      evidence = rows_for([20, 0])
      Pagination.review!(pages_for(%w[/events /events?page=1]), evidence)
      assert_equal true, evidence.last.dig(:pagination, :trailing_empty)
    end

    private

    def pages_for(paths, shared_uri: false)
      paths.each_with_index.map do |path, i|
        Page.new(id: i + 1, url: "https://example.org#{path}", website_id: 2,
          discovery_target_website_id: nil, language: "fr", rdf_uri: shared_uri ? "calendar" : "calendar-#{i}")
      end
    end

    def rows_for(counts)
      counts.each_with_index.map { |count, i| { webpage_id: i + 1, status: "event", count: count } }
    end
  end
end
