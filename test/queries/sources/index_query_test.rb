require "test_helper"

class Sources::IndexQueryTest < ActiveSupport::TestCase
  setup do
    @source_a = Source.create!(
      algorithm_value: "query alpha selector",
      selected: true,
      selected_by: "Operator",
      auto_review: true,
      language: "en",
      render_js: false,
      property: properties(:one),
      website: websites(:one),
      updated_at: 3.days.ago
    )

    @source_b = Source.create!(
      algorithm_value: "query beta rendered",
      selected: false,
      selected_by: "Operator",
      auto_review: false,
      language: "fr",
      render_js: true,
      property: properties(:two),
      website: websites(:two),
      updated_at: 1.day.ago
    )

    @source_c = Source.create!(
      algorithm_value: "query gamma newest",
      selected: true,
      selected_by: "Operator",
      auto_review: false,
      language: "en",
      render_js: false,
      property: properties(:two),
      website: websites(:two),
      updated_at: Time.zone.now
    )
  end

  test "filters by algorithm value term" do
    records = Sources::IndexQuery.call(filters: { term: "rendered" }, sort: "algorithm_value", direction: "asc", page: 1, per_page: 50)

    assert_equal [@source_b.id], records.map(&:id)
  end

  test "filters by selected" do
    records = Sources::IndexQuery.call(filters: { term: "query", selected: "false" }, sort: "algorithm_value", direction: "asc", page: 1, per_page: 50)

    assert_equal [@source_b.id], records.map(&:id)
  end

  test "filters by auto review" do
    records = Sources::IndexQuery.call(filters: { term: "query", auto_review: "true" }, sort: "algorithm_value", direction: "asc", page: 1, per_page: 50)

    assert_equal [@source_a.id], records.map(&:id)
  end

  test "filters by language" do
    records = Sources::IndexQuery.call(filters: { term: "query", language: "fr" }, sort: "algorithm_value", direction: "asc", page: 1, per_page: 50)

    assert_equal [@source_b.id], records.map(&:id)
  end

  test "filters by render js" do
    records = Sources::IndexQuery.call(filters: { term: "query", render_js: "true" }, sort: "algorithm_value", direction: "asc", page: 1, per_page: 50)

    assert_equal [@source_b.id], records.map(&:id)
  end

  test "filters by website id" do
    records = Sources::IndexQuery.call(filters: { term: "query", website_id: websites(:one).id }, sort: "algorithm_value", direction: "asc", page: 1, per_page: 50)

    assert_includes records.map(&:id), @source_a.id
    assert_not_includes records.map(&:id), @source_b.id
  end

  test "filters by property id" do
    records = Sources::IndexQuery.call(filters: { term: "query", property_id: properties(:one).id }, sort: "algorithm_value", direction: "asc", page: 1, per_page: 50)

    assert_equal [@source_a.id], records.map(&:id)
  end

  test "sorts by algorithm value" do
    records = Sources::IndexQuery.call(filters: { term: "query" }, sort: "algorithm_value", direction: "asc", page: 1, per_page: 50)

    assert_operator records.index(@source_a), :<, records.index(@source_b)
  end

  test "sorts by selected" do
    records = Sources::IndexQuery.call(filters: { term: "query" }, sort: "selected", direction: "asc", page: 1, per_page: 50)

    assert_equal false, records.first.selected
  end

  test "sorts by auto review" do
    records = Sources::IndexQuery.call(filters: { term: "query" }, sort: "auto_review", direction: "desc", page: 1, per_page: 50)

    assert_equal true, records.first.auto_review
  end

  test "sorts by language" do
    records = Sources::IndexQuery.call(filters: { term: "query" }, sort: "language", direction: "asc", page: 1, per_page: 50)

    assert_operator records.index(@source_a), :<, records.index(@source_b)
  end

  test "sorts by updated at" do
    records = Sources::IndexQuery.call(filters: { term: "query" }, sort: "updated_at", direction: "desc", page: 1, per_page: 50)

    assert_equal @source_c.id, records.first.id
  end

  test "falls back on invalid sort" do
    records = Sources::IndexQuery.call(filters: { term: "query" }, sort: "bogus", direction: "asc", page: 1, per_page: 50)

    assert_equal @source_a.id, records.first.id
  end

  test "falls back on invalid direction" do
    records = Sources::IndexQuery.call(filters: { term: "query" }, sort: "updated_at", direction: "sideways", page: 1, per_page: 50)

    assert_equal @source_a.id, records.first.id
  end

  test "paginates" do
    page_one = Sources::IndexQuery.call(filters: { term: "query" }, sort: "algorithm_value", direction: "asc", page: 1, per_page: 1)
    page_two = Sources::IndexQuery.call(filters: { term: "query" }, sort: "algorithm_value", direction: "asc", page: 2, per_page: 1)

    assert_equal 1, page_one.length
    assert_equal 1, page_two.length
    assert_not_equal page_one.first.id, page_two.first.id
  end
end
