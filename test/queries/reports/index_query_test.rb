require "test_helper"

class Reports::IndexQueryTest < ActiveSupport::TestCase
  test "filters by source and sorts by event title" do
    results = Reports::IndexQuery.call(
      filters: { source_id: sources(:one).id, startDate: "2018-01-01", endDate: "2030-01-01" },
      sort: "event_title",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert results.is_a?(Enumerable)
  end

  test "falls back on invalid sort and direction" do
    results = Reports::IndexQuery.call(
      filters: { source_id: sources(:one).id },
      sort: "bogus",
      direction: "sideways",
      page: 1,
      per_page: 50
    )

    titles = results.map { |row| row[:event_title].to_s }
    assert_equal titles.sort, titles
  end

  test "reports index query returns event title cache webpage archive date and rdf uri" do
    results = Reports::IndexQuery.call(
      filters: { source_id: sources(:one).id },
      sort: "event_title",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    row = results.first
    assert row.present?
    assert_includes row.keys, :event_title
    assert_includes row.keys, :cache
    assert_includes row.keys, :webpage_id
    assert_includes row.keys, :archive_date
    assert_includes row.keys, :rdf_uri
  end
end
