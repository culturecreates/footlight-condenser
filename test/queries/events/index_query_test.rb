require "test_helper"

class Events::IndexQueryTest < ActiveSupport::TestCase
  test "filters by date range and sorts by title" do
    results = Events::IndexQuery.call(
      filters: { seedurl: "one", startDate: "2018-01-01", endDate: "2030-01-01" },
      sort: "title",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert results.all? { |row| row[:title].present? }
  end

  test "falls back on invalid sort and direction" do
    results = Events::IndexQuery.call(
      filters: { seedurl: "one" },
      sort: "bogus",
      direction: "sideways",
      page: 1,
      per_page: 50
    )

    titles = results.map { |row| row[:title] }
    assert_equal titles.sort, titles
  end
end
