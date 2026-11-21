require "test_helper"

class Distillator::CapabilityMapTest < ActiveSupport::TestCase
  test "capability map exposes the expected sections and ladder" do
    result = Distillator::CapabilityMap.call

    assert_equal(
      [
        "Fetch & Cache",
        "Statement Extraction",
        "Sources / DSL",
        "JSON-LD Export",
        "Transition / Rollout",
        "Diagnostics / Reports",
        "Operations / Safety",
        "Legacy Wringer Compatibility"
      ],
      result.sections.map(&:title)
    )

    assert_equal(
      [
        "Fetch parity",
        "Statement parity",
        "Export parity",
        "Review activation",
        "Active rollout",
        "Rollback path"
      ],
      result.activation_readiness_ladder.map(&:name)
    )
  end

  test "capability map includes key operator features with evidence and links" do
    result = Distillator::CapabilityMap.call
    features = result.sections.flat_map(&:features).index_by(&:name)

    assert_equal "/condenser/cache/compare", features.fetch("Cache compare").operator_path
    assert_includes features.fetch("Cache compare").badges, "Read-only"

    assert_equal "/statements/compare_extracted", features.fetch("Extracted statement parity").operator_path
    assert_includes features.fetch("Extracted statement parity").badges, "Transition-only"

    assert_equal "/distillator/shadow_report", features.fetch("Export graph diff").operator_path
    assert_includes features.fetch("Export graph diff").badges, "Production-critical"

    assert_equal "/distillator/shadow_report", features.fetch("Transition report").operator_path
    assert_includes features.fetch("Transition report").badges, "Read-only"

    assert_equal "/distillator/shadow_report", features.fetch("Rollback path").operator_path
    assert_includes features.fetch("Rollback path").badges, "Writes data"

    assert_equal "/websites/wring", features.fetch("Legacy Wringer compatibility endpoint").operator_path
    assert_includes features.fetch("Legacy Wringer compatibility endpoint").badges, "Legacy-backed"
  end

  test "every feature row exposes the required fields" do
    Distillator::CapabilityMap.call.sections.each do |section|
      section.features.each do |feature|
        assert feature.name.present?
        assert feature.purpose.present?
        assert feature.implementation_status.present?
        assert feature.wringer_dependency_status.present?
        assert feature.transition_relevance.present?
        assert feature.evidence_source.present?
        assert feature.operator_label.present?
        assert feature.operator_path.present?
        assert feature.badges.present?
      end
    end
  end
end
