require "test_helper"

class UnitBoundaryTest < ActiveSupport::TestCase
  UNIT_FAST_FILES = %w[
    test/helpers/statements_helper_test.rb
    test/services/dsl_contract_test.rb
    test/services/dsl_algorithm_runner_test.rb
  ].freeze

  test "unit-fast files do not use VCR" do
    UNIT_FAST_FILES.each do |path|
      source = File.read(Rails.root.join(path))
      refute_match(/\bVCR\b/, source, "#{path} must remain unit-fast; move recorded HTTP tests to integration")
    end
  end

  test "unit-fast files do not stub localhost wring requests directly" do
    UNIT_FAST_FILES.each do |path|
      source = File.read(Rails.root.join(path))
      refute_match(/localhost:(3000|3009).*websites\/wring/, source, "#{path} should use in-memory/mocked seams, not localhost wring stubs")
    end
  end
end
