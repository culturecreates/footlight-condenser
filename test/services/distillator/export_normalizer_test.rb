require "test_helper"

class Distillator::ExportNormalizerTest < ActiveSupport::TestCase
  test "normalizes JSON deterministically" do
    input = {
      "updated_at" => "2026-04-27T12:00:00Z",
      "b" => [" two  spaces ", "one"],
      "a" => { "z" => 1, "created_at" => "2026-04-27T12:00:00Z" }
    }

    assert_equal <<~JSON.strip, Distillator::ExportNormalizer.normalize(input)
      {
        "a": {
          "z": 1
        },
        "b": [
          "one",
          "two spaces"
        ]
      }
    JSON
  end

  test "sorts JSON-LD graph nodes and preserves semantic date fields" do
    input = [
      { "@id" => "event:b", "startDate" => "2026-05-02T20:00:00Z" },
      { "@id" => "event:a", "startDate" => "2026-05-01T20:00:00Z" }
    ]

    normalized = Distillator::ExportNormalizer.normalize(input)

    assert_operator normalized.index("event:a"), :<, normalized.index("event:b")
    assert_includes normalized, "2026-05-01T20:00:00Z"
    assert_includes normalized, "2026-05-02T20:00:00Z"
  end

  test "normalizes RDF-ish line output" do
    input = <<~TEXT
      <event:b>   <name>   "Beta" .

      <event:a> <updated_at> "2026-04-27T12:00:00Z" .
      <event:a>   <name>   "Alpha" .
    TEXT

    assert_equal <<~TEXT.strip, Distillator::ExportNormalizer.normalize(input)
      <event:a> <name> "Alpha" .
      <event:b> <name> "Beta" .
    TEXT
  end
end
