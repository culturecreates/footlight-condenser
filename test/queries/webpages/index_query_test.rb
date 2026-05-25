require "test_helper"

class Webpages::IndexQueryTest < ActiveSupport::TestCase
  setup do
    @website_one = Website.create!(
      name: "Query website one",
      seedurl: "query-website-one",
      graph_name: "https://example.org/query-website-one",
      default_language: "en"
    )
    @website_two = Website.create!(
      name: "Query website two",
      seedurl: "query-website-two",
      graph_name: "https://example.org/query-website-two",
      default_language: "en"
    )
    @event_class = rdfs_classes(:one)
    @place_class = rdfs_classes(:place)
    @other_class = rdfs_classes(:two)

    @active_publishable_event = Webpage.create!(
      url: "https://example.org/query-active-publishable",
      language: "en",
      rdf_uri: "footlight:active-publishable-query",
      rdfs_class: @event_class,
      website: @website_one,
      archive_date: 8.days.from_now,
      updated_at: 1.day.ago
    )
    create_publishable_statements_for(@active_publishable_event)

    @archived_publishable_event = Webpage.create!(
      url: "https://example.org/query-archived-publishable",
      language: "fr",
      rdf_uri: "footlight:archived-publishable-query",
      rdfs_class: @event_class,
      website: @website_one,
      archive_date: 2.days.ago,
      updated_at: 3.days.ago
    )
    create_publishable_statements_for(@archived_publishable_event)

    @internal_event = Webpage.create!(
      url: "footlight:internal-event-query",
      language: "en",
      rdf_uri: "footlight:internal-event-query",
      rdfs_class: @event_class,
      website: @website_one,
      archive_date: 8.days.from_now,
      updated_at: 2.days.ago
    )

    @other_page = Webpage.create!(
      url: "footlight:other-query",
      language: "en",
      rdf_uri: "footlight:other-query",
      rdfs_class: @other_class,
      website: @website_one,
      archive_date: 8.days.from_now,
      updated_at: 4.days.ago
    )

    @place_page = Webpage.create!(
      url: "http://example.org/query-place",
      language: "en",
      rdf_uri: "footlight:place-query",
      rdfs_class: @place_class,
      website: @website_two,
      archive_date: 5.days.from_now,
      updated_at: Time.zone.now
    )

    @website_two_publishable_event = Webpage.create!(
      url: "https://example.org/query-site-two-publishable",
      language: "en",
      rdf_uri: "footlight:site-two-publishable-query",
      rdfs_class: @event_class,
      website: @website_two,
      archive_date: 10.days.from_now,
      updated_at: 30.minutes.ago
    )
    create_publishable_statements_for(@website_two_publishable_event)
  end

  test "default query returns active publishable event webpages only" do
    records = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id },
      sort: "url",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert_equal [@active_publishable_event.id], records.map(&:id)
  end

  test "default query excludes non publishable non event and archived webpages" do
    records = Webpages::IndexQuery.call(
      filters: {},
      sort: "url",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert_includes records.map(&:id), @active_publishable_event.id
    assert_includes records.map(&:id), @website_two_publishable_event.id
    assert_not_includes records.map(&:id), @archived_publishable_event.id
    assert_not_includes records.map(&:id), @internal_event.id
    assert_not_includes records.map(&:id), @other_page.id
    assert_not_includes records.map(&:id), @place_page.id
  end

  test "scope all returns all webpages for selected website" do
    records = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id, scope: "all" },
      sort: "url",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert_equal [
      @active_publishable_event.id,
      @archived_publishable_event.id,
      @internal_event.id,
      @other_page.id
    ].sort, records.map(&:id).sort
  end

  test "scope all publishable false returns only non publishable webpages" do
    records = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id, scope: "all", publishable: "false" },
      sort: "url",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert_equal [@internal_event.id, @other_page.id].sort, records.map(&:id).sort
  end

  test "publishable false outside scope all falls back to default publishable scope" do
    records = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id, publishable: "false" },
      sort: "url",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert_equal [@active_publishable_event.id], records.map(&:id)
  end

  test "scope all filters by publishable true" do
    records = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id, scope: "all", publishable: "true" },
      sort: "url",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert_equal [@active_publishable_event.id, @archived_publishable_event.id].sort, records.map(&:id).sort
  end

  test "scope all archive filter still applies within the broader base scope" do
    records = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id, scope: "all", archive_state: "archived" },
      sort: "url",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert_equal [@archived_publishable_event.id], records.map(&:id)
  end

  test "scope all filters by public source urls" do
    records = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id, scope: "all", url_kind: "public" },
      sort: "url",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert_includes records.map(&:id), @active_publishable_event.id
    assert_includes records.map(&:id), @archived_publishable_event.id
    assert_not_includes records.map(&:id), @internal_event.id
  end

  test "scope all filters by internal uris" do
    records = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id, scope: "all", url_kind: "internal" },
      sort: "url",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert_equal [@internal_event.id, @other_page.id].sort, records.map(&:id).sort
  end

  test "scope all filters by rdfs class name" do
    records = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id, scope: "all", rdfs_class: "Event" },
      sort: "url",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert_equal [
      @active_publishable_event.id,
      @archived_publishable_event.id,
      @internal_event.id
    ].sort, records.map(&:id).sort
  end

  test "filters other class bucket as nil or unbucketed classes" do
    nil_class_page = Webpage.create!(
      url: "footlight:nil-class-query",
      language: "en",
      rdf_uri: "footlight:nil-class-query",
      rdfs_class: @event_class,
      website: @website_one,
      archive_date: 8.days.from_now
    )
    nil_class_page.update_column(:rdfs_class_id, nil)

    records = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id, scope: "all", rdfs_class: "Other" },
      sort: "url",
      direction: "asc",
      page: 1,
      per_page: 50
    )

    assert_includes records.map(&:id), @other_page.id
    assert_includes records.map(&:id), nil_class_page.id
    assert_not_includes records.map(&:id), @active_publishable_event.id
  end

  test "paginate false returns all matching rows" do
    30.times do |index|
      webpage = Webpage.create!(
        url: "https://example.org/query-many-#{index}",
        language: "en",
        rdf_uri: "footlight:many-query:#{index}",
        rdfs_class: @event_class,
        website: @website_one,
        archive_date: 10.days.from_now
      )
      create_publishable_statements_for(webpage, algorithm_value: "paginate-false-#{index}")
    end

    records = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id },
      sort: "url",
      direction: "asc",
      page: 2,
      per_page: 1,
      paginate: false
    )

    assert_equal 31, records.length
  end

  test "paginate true still paginates when requested" do
    page_one = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id, scope: "all" },
      sort: "url",
      direction: "asc",
      page: 1,
      per_page: 1
    )
    page_two = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id, scope: "all" },
      sort: "url",
      direction: "asc",
      page: 2,
      per_page: 1
    )

    assert_equal 1, page_one.length
    assert_equal 1, page_two.length
    assert_not_equal page_one.first.id, page_two.first.id
  end

  test "sorts by updated at within the selected scope" do
    records = Webpages::IndexQuery.call(
      filters: { scope: "all" },
      sort: "updated_at",
      direction: "desc",
      page: 1,
      per_page: 50
    )

    assert_equal @place_page.id, records.first.id
  end

  test "falls back on invalid sort and direction" do
    records = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id, scope: "all" },
      sort: "bogus",
      direction: "sideways",
      page: 1,
      per_page: 50
    )
    expected = Webpages::IndexQuery.call(
      filters: { website_id: @website_one.id, scope: "all" },
      sort: Webpages::IndexQuery::DEFAULT_SORT,
      direction: Webpages::IndexQuery::DEFAULT_DIRECTION,
      page: 1,
      per_page: 50
    )

    assert_equal expected.map(&:id), records.map(&:id)
  end

  private

  def create_publishable_statements_for(webpage, algorithm_value: "query-test")
    [
      [properties(:four), "Publishable title"],
      [properties(:location), '[["Salle","uri:place"]]'],
      [properties(:six), '["2026-06-01T20:00:00-04:00"]']
    ].each do |property, cache|
      source = Source.create!(
        website: webpage.website,
        property: property,
        language: "en",
        selected: true,
        algorithm_value: algorithm_value
      )

      Statement.create!(
        webpage: webpage,
        source: source,
        cache: cache,
        status: "ok"
      )
      Statement.where(webpage: webpage, source: source).update_all(status: "ok")
    end
  end
end
