require "test_helper"

class Properties::IndexQueryTest < ActiveSupport::TestCase
  test "sorts by label and paginates" do
    results = Properties::IndexQuery.call(filters: {}, sort: "label", direction: "asc", page: 1, per_page: 2)

    assert_operator results.length, :<=, 2
    assert_equal results.map(&:label).sort, results.map(&:label)
  end

  test "falls back on invalid sort and direction" do
    results = Properties::IndexQuery.call(filters: {}, sort: "bogus", direction: "sideways", page: 1, per_page: 50)

    assert_equal Property.order(:label).limit(results.length).pluck(:label), results.map(&:label)
  end
end
