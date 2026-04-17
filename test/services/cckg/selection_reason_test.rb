require 'test_helper'
require_dependency 'cckg/selection_reason'

class CckgSelectionReasonTest < ActiveSupport::TestCase
  def test_returns_exact_when_selected_hit_matches_query
    reason = Cckg::SelectionReason.for(
      query: 'Esplanade de la Place des Arts',
      selected_hits: [
        { 'name' => 'Esplanade de la Place des Arts', 'match' => false, 'description' => 'Montreal (QC) CA' }
      ],
      province: 'ON'
    )

    assert_equal 'exact', reason
  end

  def test_returns_province_when_selected_hit_matches_province
    reason = Cckg::SelectionReason.for(
      query: 'Grand Theatre',
      selected_hits: [
        { 'name' => 'Grand Theatre Ontario', 'match' => false, 'description' => 'Sudbury (ON) CA' }
      ],
      province: 'ON'
    )

    assert_equal 'province', reason
  end

  def test_returns_fallback_score_when_no_exact_or_province_match
    reason = Cckg::SelectionReason.for(
      query: 'Grand Theatre',
      selected_hits: [
        { 'name' => 'Grand Theatre Quebec', 'match' => false, 'description' => 'Montreal (QC) CA' }
      ],
      province: 'ON'
    )

    assert_equal 'fallback_score', reason
  end
end
