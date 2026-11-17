require "test_helper"

class DslLibraryEntryTest < ActiveSupport::TestCase
  test "seeded library has history and body changes create revisions without changing stored sources" do
    entry = DslLibraryEntry.find_by!(name: "META_TITLE")
    source = sources(:one)
    source.update!(algorithm_value: '$$META_TITLE$$')
    original = entry.body
    assert_equal original, entry.versions.find_by!(revision: 1).body
    entry.update!(body: 'xpath=//title')
    assert_equal 2, entry.revision
    assert_equal original, entry.versions.find_by!(revision: 1).body
    assert_equal 'xpath=//title', entry.versions.find_by!(revision: 2).body
    assert_equal '$$META_TITLE$$', source.reload.algorithm_value
    assert_includes entry.references, source
  end

  test "names are stable and reserved names unknown references and cycles cannot be saved" do
    entry = DslLibraryEntry.new(name: "SELF_URL", body: 'ruby=[]')
    assert_not entry.valid?
    entry = DslLibraryEntry.create!(name: "CUSTOM_BLOCK", body: 'ruby=[]')
    assert_not entry.update(name: "RENAMED")
    entry.reload
    assert_not entry.update(body: '$$UNKNOWN_TOKEN$$')
    assert_not entry.update(body: '$$CUSTOM_BLOCK$$')
    assert_equal 1, entry.reload.revision
  end

  test "optimistic locking protects concurrent edits" do
    entry = DslLibraryEntry.find_by!(name: "ARRAY_UNIQ")
    stale = DslLibraryEntry.find(entry.id)
    entry.update!(body: 'ruby=$array')
    assert_raises(ActiveRecord::StaleObjectError) { stale.update!(body: 'ruby=[]') }
    assert_equal 2, entry.reload.revision
  end
end
