require "test_helper"
require_relative "../support/jsonld_comparator"

class JsonldComparatorTest < ActiveSupport::TestCase
  include JsonldComparator

  test "canonical_jsonld sorts hash keys recursively" do
    value = {
      "z" => { "b" => 2, "a" => 1 },
      "a" => 1
    }

    canonical = canonical_jsonld(value)

    assert_equal ["a", "z"], canonical.keys
    assert_equal ["a", "b"], canonical["z"].keys
  end

  test "canonical_jsonld strips only explicit volatile fields" do
    value = {
      "created_at" => "2026-04-24T00:00:00Z",
      "generated_at" => "2026-04-24T00:00:00Z",
      "name" => "event"
    }

    canonical = canonical_jsonld(value)

    assert_equal({ "name" => "event" }, canonical)
  end

  test "only explicitly defined volatile keys are stripped" do
    value = {
      "generated_at" => "time",
      "@id" => "SHOULD STAY"
    }

    canonical = canonical_jsonld(value)

    assert canonical.key?("@id"), "@id must not be stripped"
  end

  test "assert_jsonld_equal reports precise mismatch path" do
    expected = { "events" => [{ "location" => { "name" => "Old Hall" } }] }
    actual = { "events" => [{ "location" => { "name" => "New Hall" } }] }

    error = assert_raises(Minitest::Assertion) do
      assert_jsonld_equal(expected, actual)
    end

    assert_match("events[0].location.name", error.message)
    assert_match("\"Old Hall\"", error.message)
    assert_match("\"New Hall\"", error.message)
  end

  test "comparator does not normalize symbol vs string" do
    expected = { status: :ok }
    actual = { status: "ok" }

    error = assert_raises(Minitest::Assertion) do
      assert_jsonld_equal(expected, actual)
    end

    assert_match("status", error.message)
    assert_match(":ok", error.message)
    assert_match("\"ok\"", error.message)
  end

  test "comparator does not hide missing keys" do
    expected = { a: 1, b: 2 }
    actual = { a: 1 }

    error = assert_raises(Minitest::Assertion) do
      assert_jsonld_equal(expected, actual)
    end

    assert_match("b", error.message)
    assert_match("missing key", error.message)
  end

  test "comparator does not ignore extra keys" do
    expected = { a: 1 }
    actual = { a: 1, b: 2 }

    error = assert_raises(Minitest::Assertion) do
      assert_jsonld_equal(expected, actual)
    end

    assert_match("b", error.message)
    assert_match("unexpected key", error.message)
  end

  test "comparator is strict about nil vs missing" do
    expected = { a: nil }
    actual = {}

    error = assert_raises(Minitest::Assertion) do
      assert_jsonld_equal(expected, actual)
    end

    assert_match("a", error.message)
    assert_match("missing key", error.message)
  end

  test "canonical_jsonld sorts only explicitly unordered arrays" do
    expected = [{ "@id" => "b" }, { "@id" => "a" }]
    actual = [{ "@id" => "a" }, { "@id" => "b" }]

    assert_jsonld_equal(expected, actual)
  end

  test "array sorting uses canonical structure, not raw JSON" do
    expected = [
      { "b" => 1, "a" => 2 },
      { "a" => 2, "b" => 1 }
    ]

    assert_jsonld_equal(expected, expected.reverse)
  end

  test "unordered array with non-comparable elements raises error" do
    value = [1, { "a" => 1 }]

    assert_raises(ArgumentError) do
      canonical_jsonld(value)
    end
  end

  test "comparator does not reorder nested arrays by default" do
    expected = { "events" => ["b", "a"] }
    actual = { "events" => ["a", "b"] }

    error = assert_raises(Minitest::Assertion) do
      assert_jsonld_equal(expected, actual)
    end

    assert_match("events[0]", error.message)
  end
end
