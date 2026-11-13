require "test_helper"

class HarmonizedIndexParamsTest < ActiveSupport::TestCase
  class Harness
    include HarmonizedIndexParams

    attr_accessor :params

    def initialize(params = {})
      @params = ActionController::Parameters.new(params)
    end
  end

  test "defaults page to 1" do
    harness = Harness.new(page: "0")

    assert_equal 1, harness.send(:harmonized_index_page)
  end

  test "caps per page" do
    harness = Harness.new(per_page: "500")

    assert_equal 100, harness.send(:harmonized_index_per_page, default: 25, max: 100)
  end

  test "allows only asc and desc" do
    harness = Harness.new(direction: "asc")

    assert_equal "asc", harness.send(:harmonized_index_direction)
  end

  test "falls back on invalid direction" do
    harness = Harness.new(direction: "sideways")

    assert_equal "desc", harness.send(:harmonized_index_direction, default: "desc")
  end

  test "allows only declared sort columns" do
    harness = Harness.new(sort: "updated_at")

    assert_equal "updated_at", harness.send(:harmonized_index_sort, allowed: %w[name updated_at], default: "name")
  end

  test "falls back on invalid sort" do
    harness = Harness.new(sort: "drop table")

    assert_equal "name", harness.send(:harmonized_index_sort, allowed: %w[name updated_at], default: "name")
  end

  test "drops blank filter params" do
    harness = Harness.new(term: "  ", language: "", website_id: nil)

    assert_equal({}, harness.send(:harmonized_index_filters, allowed: %i[term language website_id]))
  end

  test "preserves valid filter params" do
    harness = Harness.new(term: "needle", language: "en", website_id: "4")

    assert_equal(
      { term: "needle", language: "en", website_id: "4" },
      harness.send(:harmonized_index_filters, allowed: %i[term language website_id])
    )
  end

  test "builds normalized index params from declared keys" do
    harness = Harness.new(
      page: "-2",
      per_page: "500",
      sort: "updated_at",
      direction: "sideways",
      term: "needle",
      language: "en",
      website_id: ""
    )

    normalized = harness.send(
      :harmonized_index_params,
      allowed_filters: %i[term language website_id],
      allowed_sorts: %w[name updated_at],
      default_sort: "name",
      default_direction: "desc",
      default_per_page: 25,
      max_per_page: 100
    )

    assert_equal(
      {
        filters: { term: "needle", language: "en" },
        sort: "updated_at",
        direction: "desc",
        page: 1,
        per_page: 100
      },
      normalized
    )
  end

  test "canonical params preserve declared route params" do
    harness = Harness.new
    index_params = {
      filters: { term: "needle" },
      sort: "updated_at",
      direction: "desc",
      page: 2,
      per_page: 50
    }

    canonical = harness.send(
      :harmonized_index_canonical_params,
      index_params,
      default_sort: "name",
      default_direction: "asc",
      default_per_page: 25,
      preserve: { seedurl: "one" }
    )

    assert_equal(
      {
        "seedurl" => "one",
        "term" => "needle",
        "sort" => "updated_at",
        "direction" => "desc",
        "page" => "2",
        "per_page" => "50"
      },
      canonical
    )
  end

  test "canonical params omit default sort direction page and per_page" do
    harness = Harness.new
    index_params = {
      filters: { term: "needle" },
      sort: "name",
      direction: "asc",
      page: 1,
      per_page: 25
    }

    canonical = harness.send(
      :harmonized_index_canonical_params,
      index_params,
      default_sort: "name",
      default_direction: "asc",
      default_per_page: 25
    )

    assert_equal({ "term" => "needle" }, canonical)
  end

  test "canonical params drop blank filters" do
    harness = Harness.new
    index_params = {
      filters: { term: "needle", language: "", website_id: nil },
      sort: "name",
      direction: "asc",
      page: 1,
      per_page: 25
    }

    canonical = harness.send(
      :harmonized_index_canonical_params,
      index_params,
      default_sort: "name",
      default_direction: "asc",
      default_per_page: 25
    )

    assert_equal({ "term" => "needle" }, canonical)
  end

  test "canonical params can exclude route scoped filters from query string" do
    harness = Harness.new
    index_params = {
      filters: { seedurl: "one", term: "needle" },
      sort: "name",
      direction: "asc",
      page: 1,
      per_page: 25
    }

    canonical = harness.send(
      :harmonized_index_canonical_params,
      index_params,
      default_sort: "name",
      default_direction: "asc",
      default_per_page: 25,
      exclude_filters: [:seedurl]
    )

    assert_equal({ "term" => "needle" }, canonical)
  end

  test "raw params include only declared filters and preserved params" do
    harness = Harness.new(
      term: "needle",
      language: "en",
      ignored: "value",
      page: "2",
      per_page: "10",
      seedurl: "one",
      sort: "updated_at",
      direction: "desc"
    )

    raw = harness.send(
      :harmonized_index_raw_params,
      allowed_filters: %i[term language],
      preserve: %w[seedurl sort direction page per_page]
    )

    assert_equal(
      {
        "term" => "needle",
        "language" => "en",
        "seedurl" => "one",
        "sort" => "updated_at",
        "direction" => "desc",
        "page" => "2",
        "per_page" => "10"
      },
      raw
    )
  end
end
