require "test_helper"

class Distillator::Cohorts::LavitrinePipelineTest < ActiveSupport::TestCase
  test "exposes the versioned la vitrine feed names" do
    assert_equal "https://raw.githubusercontent.com/artsdata-stewards/artsdata-actions/main/queries/lavitrine_pipeline.sparql",
                 Distillator::Cohorts::LavitrinePipeline.query_url
    assert_includes Distillator::Cohorts::LavitrinePipeline.feed_names, "hector-charland-com"
    assert_includes Distillator::Cohorts::LavitrinePipeline.feed_names, "derived-grandtheatre-qc-ca"
    assert_includes Distillator::Cohorts::LavitrinePipeline.feed_names, "culture-mauricie"
  end
end
