require "test_helper"

class Webpages::IndexQueryTest < ActiveSupport::TestCase
  setup do
    @website_one = websites(:one)
    @website_two = websites(:two)
    @event_class = rdfs_classes(:one)
    @place_class = rdfs_classes(:place)

    @archived = Webpage.create!(
      url: "http://example.org/query-archived",
      language: "fr",
      rdf_uri: "footlight:archived-query",
      rdfs_class: @event_class,
      website: @website_one,
      archive_date: 2.days.ago,
      updated_at: 3.days.ago
    )

    @active = Webpage.create!(
      url: "http://example.org/query-active",
      language: "en",
      rdf_uri: "footlight:active-query",
      rdfs_class: @place_class,
      website: @website_two,
      archive_date: 5.days.from_now,
      updated_at: 1.day.ago
    )

    @latest = Webpage.create!(
      url: "http://example.org/query-z-latest",
      language: "en",
      rdf_uri: "footlight:latest-query",
      rdfs_class: @event_class,
      website: @website_one,
      archive_date: 10.days.from_now,
      updated_at: Time.zone.now
    )
  end

  test "filters by url term" do
    records = Webpages::IndexQuery.call(filters: { term: "active-query" }, sort: "url", direction: "asc", page: 1, per_page: 50)

    assert_equal [@active.id], records.map(&:id)
  end

  test "filters by website id" do
    records = Webpages::IndexQuery.call(filters: { term: "query-", website_id: @website_two.id }, sort: "url", direction: "asc", page: 1, per_page: 50)

    assert_equal [@active.id], records.map(&:id)
  end

  test "filters by language" do
    records = Webpages::IndexQuery.call(filters: { term: "query-", language: "fr" }, sort: "url", direction: "asc", page: 1, per_page: 50)

    assert_equal [@archived.id], records.map(&:id)
  end

  test "filters by rdfs class id" do
    records = Webpages::IndexQuery.call(filters: { term: "query-", rdfs_class_id: @place_class.id }, sort: "url", direction: "asc", page: 1, per_page: 50)

    assert_equal [@active.id], records.map(&:id)
  end

  test "filters by archive state when archive date exists" do
    archived_records = Webpages::IndexQuery.call(filters: { term: "query-", archive_state: "archived" }, sort: "url", direction: "asc", page: 1, per_page: 50)
    active_records = Webpages::IndexQuery.call(filters: { term: "query-", archive_state: "active" }, sort: "url", direction: "asc", page: 1, per_page: 50)

    assert_includes archived_records.map(&:id), @archived.id
    assert_includes active_records.map(&:id), @active.id
    assert_includes active_records.map(&:id), @latest.id
    assert_not_includes active_records.map(&:id), @archived.id
  end

  test "sorts by url" do
    records = Webpages::IndexQuery.call(filters: { term: "query-" }, sort: "url", direction: "asc", page: 1, per_page: 50)

    assert_operator records.index(@active), :<, records.index(@latest)
  end

  test "sorts by website id" do
    records = Webpages::IndexQuery.call(filters: { term: "query-" }, sort: "website_id", direction: "asc", page: 1, per_page: 50)

    first_website_id = records.first.website_id
    assert_equal [@website_one.id, @website_two.id].min, first_website_id
  end

  test "sorts by language" do
    records = Webpages::IndexQuery.call(filters: { term: "query-" }, sort: "language", direction: "asc", page: 1, per_page: 50)

    assert_operator records.index(@active), :<, records.index(@archived)
  end

  test "sorts by updated at" do
    records = Webpages::IndexQuery.call(filters: { term: "query-" }, sort: "updated_at", direction: "desc", page: 1, per_page: 50)

    assert_equal @latest.id, records.first.id
  end

  test "falls back on invalid sort" do
    records = Webpages::IndexQuery.call(filters: { term: "query-" }, sort: "bogus", direction: "asc", page: 1, per_page: 50)

    assert_equal @active.id, records.first.id
  end

  test "falls back on invalid direction" do
    records = Webpages::IndexQuery.call(filters: { term: "query-" }, sort: "updated_at", direction: "sideways", page: 1, per_page: 50)

    assert_equal @archived.id, records.first.id
  end

  test "paginates" do
    page_one = Webpages::IndexQuery.call(filters: { term: "query-" }, sort: "url", direction: "asc", page: 1, per_page: 1)
    page_two = Webpages::IndexQuery.call(filters: { term: "query-" }, sort: "url", direction: "asc", page: 2, per_page: 1)

    assert_equal 1, page_one.length
    assert_equal 1, page_two.length
    assert_not_equal page_one.first.id, page_two.first.id
  end
end
