require "test_helper"

class Distillator::MigrationStatusTest < ActiveSupport::TestCase
  test "reports compact readiness checks and known legacy bypasses" do
    status = Distillator::MigrationStatus.call

    assert_equal true, status.dig(:checks, "Fetch cache model present")
    assert_equal true, status.dig(:checks, "Export invariance fixture")
    assert_equal true, status.dig(:checks, "Render-JS fallback coverage")
    assert_equal true, status.dig(:checks, "JSON POST fallback coverage")
    assert_equal true, status.dig(:checks, "Manual link export coverage")
    assert_equal 0, status.dig(:legacy_bypasses, :count)
  end
end
