require "test_helper"

class Statements::IndexQueryTest < ActiveSupport::TestCase
  test "filters by cache and status" do
    results = Statements::IndexQuery.call(
      filters: { cache: "MyString", status: "initial" },
      sort: "cache",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert results.all? { |statement| statement.cache.include?("MyString") }
    assert results.all? { |statement| statement.status == "initial" }
  end

  test "falls back on invalid sort and direction" do
    results = Statements::IndexQuery.call(filters: {}, sort: "bogus", direction: "sideways", page: 1, per_page: 50)

    assert_equal Statement.order(:id).limit(results.length).pluck(:id), results.map(&:id)
  end
end
