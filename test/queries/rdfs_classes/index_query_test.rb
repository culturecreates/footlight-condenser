require "test_helper"

class RdfsClasses::IndexQueryTest < ActiveSupport::TestCase
  test "sorts by name and paginates" do
    results = RdfsClasses::IndexQuery.call(filters: {}, sort: "name", direction: "asc", page: 1, per_page: 2)

    assert_operator results.length, :<=, 2
    assert_equal results.map(&:name).sort, results.map(&:name)
  end

  test "falls back on invalid sort and direction" do
    results = RdfsClasses::IndexQuery.call(filters: {}, sort: "bogus", direction: "sideways", page: 1, per_page: 50)

    assert_equal RdfsClass.order(:name).limit(results.length).pluck(:name), results.map(&:name)
  end
end
