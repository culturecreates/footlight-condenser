# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../app/services/resource_lists/link_inventory"

class LinkInventoryTest < Minitest::Test
  def digest(values)
    ResourceLists::LinkInventory.fingerprint(values)
  end

  def test_reordered_and_duplicated_links_have_same_inventory
    assert_equal digest(["/about", "/event-a", "/event-a"]),
      digest(["/event-a", "/about"])
  end

  def test_distinct_event_links_change_inventory_despite_equal_anchor_count
    refute_equal digest(["/about", "/event-a"]),
      digest(["/about", "/event-b"])
  end

  def test_ignores_blank_anchor_destinations
    assert_equal digest(["/about"]), digest(["  ", "/about", "/about"])
  end

  def test_empty_inventory_cannot_be_used_as_progress_evidence
    assert_nil digest([])
    assert_nil digest(["", " "])
  end

  def test_rejects_invalid_href_data
    assert_raises(ArgumentError) { digest(nil) }
    assert_raises(ArgumentError) { digest(["/about", nil]) }
  end
end
