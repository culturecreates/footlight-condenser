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

  test "pagination preserves the total and returns the requested page" do
    query = query_with_events(125, page: 2, per_page: 25)

    results = query.call

    assert_equal 125, results.total_entries
    assert_equal 25, results.length
    assert_equal "event:026", results.first[:rdf_uri]
    assert_equal "event:050", results.last[:rdf_uri]
  end

  test "unpaginated queries return all events beyond both HTML page limits" do
    results = query_with_events(125, page: 2, per_page: 100, paginate: false).call

    assert_equal 125, results.length
    assert_equal 125, results.map { |row| row[:rdf_uri] }.uniq.length
    assert_equal "event:001", results.first[:rdf_uri]
    assert_equal "event:125", results.last[:rdf_uri]
  end

  test "unpaginated queries retain search and descending sort" do
    results = query_with_events(125, paginate: false, term: "Event 12", direction: "desc").call

    assert_equal (120..125).to_a.reverse.map { |id| "event:#{id}" }, results.map { |row| row[:rdf_uri] }
    assert results.all? { |row| row[:statements_status][:publishable] }
  end

  test "unpaginated queries preserve an empty result" do
    assert_empty query_with_events(0, paginate: false).call
  end

  private

  def query_with_events(count, page: 1, per_page: 25, paginate: true, term: nil, direction: "asc")
    query = Events::IndexQuery.new(
      filters: { seedurl: "one", term: term }, sort: "title", direction: direction,
      page: page, per_page: per_page, paginate: paginate
    )
    rows = (1..count).to_h do |id|
      number = format("%03d", id)
      ["event:#{number}", {
        "title" => { cache: "Event #{number}", status: "ok" },
        "dates" => { cache: "2030-01-01", status: "ok" },
        "location" => { cache: "Venue", status: "ok" },
        archive_date: { cache: Date.new(2030, 1, 2) }
      }]
    end
    query.stubs(:website_statements_by_event).returns(rows)
    query
  end
end
