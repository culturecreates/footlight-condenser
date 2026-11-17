require "test_helper"

class PreprocessingPolicyTest < ActiveSupport::TestCase
  include PreprocessingTestSupport
  setup { build_preprocessing_fixture }

  test "requires exact expected website and rejects wrong input identities" do
    @policy.destroy!
    policy = PreprocessingPolicy.new(statement_id: @target.id, expected_seedurl: "another-site", enabled: false)
    assert_not policy.valid?
    assert_includes policy.errors.full_messages.join, "Expected website"
    policy.expected_seedurl = @website.seedurl
    assert policy.valid?
    policy.enabled = true
    assert_not policy.valid?
    policy.inputs_verified = true
    policy.input_statement_ids = [statements(:one).id]
    assert_not policy.valid?
    policy.input_statement_ids = [@input.id]
    assert policy.valid?
  end

  test "draft defaults are safe and explicit external-input policies can run outside ResourceList sites" do
    @policy.update!(enabled: false)
    @list.destroy!
    assert @policy.update(input_statement_ids: [], enabled: true)
    assert @policy.enabled?
    assert_equal false, PreprocessingPolicy.new.enabled
  end

  test "invalid interval and input IDs are rejected" do
    [[0,48], [12,4], [169,200]].each do |interval, stale|
      @policy.assign_attributes(interval_hours: interval, stale_after_hours: stale)
      assert_not @policy.valid?
    end
    @policy.assign_attributes(interval_hours: 12, stale_after_hours: 48)
    [[@target.id], [@input.id,@input.id], ["wrong"], [-1]].each do |ids|
      @policy.input_statement_ids = ids
      assert_not @policy.valid?
    end
  end

  test "missing target does not prevent disabling the policy" do
    @target.destroy!
    assert @policy.update(enabled: false)
    assert_not @policy.enabled?
  end
end
