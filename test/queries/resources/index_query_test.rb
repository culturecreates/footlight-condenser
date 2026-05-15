require "test_helper"

class Resources::IndexQueryTest < ActiveSupport::TestCase
  test "returns resource rows for a seedurl" do
    results = Resources::IndexQuery.call(
      filters: { seedurl: websites(:one).seedurl },
      sort: "rdf_uri",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert results.any?
    assert results.all? { |row| row[:rdf_uri].present? }
  end

  test "falls back on invalid sort and direction" do
    results = Resources::IndexQuery.call(
      filters: { seedurl: websites(:one).seedurl },
      sort: "bogus",
      direction: "sideways",
      page: 1,
      per_page: 50
    )

    sorted = results.map { |row| row[:rdf_uri] }
    assert_equal sorted.sort, sorted
  end
end
