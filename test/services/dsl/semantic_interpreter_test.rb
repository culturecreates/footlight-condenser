require "test_helper"

class Dsl::SemanticInterpreterTest < ActiveSupport::TestCase
  test "empty to non-empty is Δ added" do
    si = Dsl::SemanticInterpreter.new
    assert_equal "Δ added", si.semantic([], ["A"])
  end

  test "empty to empty is no result" do
    si = Dsl::SemanticInterpreter.new
    assert_equal "No result", si.semantic([], [])
  end

  test "same value is no change" do
    si = Dsl::SemanticInterpreter.new
    assert_equal "No change", si.semantic(["A"], ["A"])
  end

  test "non-empty to empty is removed" do
    si = Dsl::SemanticInterpreter.new
    assert_equal "Δ removed", si.semantic(["A"], [])
  end

  test "different non-empty values are changed" do
    si = Dsl::SemanticInterpreter.new
    assert_equal "Δ changed", si.semantic(["A"], ["B"])
  end

  test "delta only exists for changed semantics" do
    si = Dsl::SemanticInterpreter.new

    assert_nil si.delta(["A"], ["A"], "No change")
    assert_not_nil si.delta(["A"], ["B"], "Δ changed")
  end

  test "intent classification follows type and code" do
    si = Dsl::SemanticInterpreter.new

    assert_equal "extraction", si.intent(type: "xpath")
    assert_equal "filter", si.intent(type: "ruby", code: "reject")
  end

  test "annotate keeps summary-string delta compatibility" do
    si = Dsl::SemanticInterpreter.new
    steps = [
      { step: 1, type: "ruby", output: "[1 items: seed]" },
      { step: 2, type: "ruby", output: "[1 items: https://example.com/a]" }
    ]

    annotated = si.annotate(steps)

    assert_equal "Δ changed", annotated.second[:semantic]
    assert_match(/\+https:\/\/example.com/, annotated.second[:delta])
    assert_match(/-seed/, annotated.second[:delta])
  end
end
