require "test_helper"

class Dsl::JolietteAvailabilityTest < ActiveSupport::TestCase
  include DslRunnerTestHelper

  test "unchanged source 7023 preserves its four SoldOut outputs under the production accumulation contract" do
    expect_no_fetch_seams
    html = fixture("sold_out")
    [Dsl::Tracing::NullTracer.new, Dsl::Tracing::TraceCollector.new].each do |tracer|
      runner, = build_runner_with_html(html: html, tracer: tracer)
      assert_equal Array.new(4, "http://schema.org/SoldOut"), runner.run(algorithm)
    end
  end

  test "unchanged original source no longer raises SafeBuffer drop errors when a purchase URL exists" do
    expect_no_fetch_seams
    runner, tracer = build_runner_with_html(html: fixture("available"))
    # Preserve this source's established output. Its tariff-to-URL business rule
    # is separate from restoring the interpreter contract.
    assert_equal %w[InStock SoldOut SoldOut].map { |status| "http://schema.org/#{status}" }, runner.run(algorithm)
    assert tracer.to_h.all? { |entry| entry[:error_message].nil? }
    saved = tracer.to_h[3][:output_full]
    assert_equal [[[], "Régulier", "Membre", "18 ans et moins"]], saved
    assert_equal 1, saved.length, "Later appends must not mutate recorded trace snapshots"
  end

  private

  def algorithm
    Rails.root.join("test/fixtures/dsl/joliette/original_availability.dsl").read
  end

  def fixture(name)
    Rails.root.join("test/fixtures/dsl/joliette/#{name}.html").read
  end
end
