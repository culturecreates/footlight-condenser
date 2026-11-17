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

  test "reserved names unknown references and cycles cannot be saved" do
    entry = DslLibraryEntry.new(name: "SELF_URL", body: 'ruby=[]')
    assert_not entry.valid?
    entry = DslLibraryEntry.create!(name: "CUSTOM_BLOCK", body: 'ruby=[]')
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
  test "rename updates complete source and nested tokens and preserves literal strings and history" do
    entry = DslLibraryEntry.find_by!(name: "META_TITLE")
    nested = DslLibraryEntry.create!(name: "TITLE_BLOCK", body: '$$META_TITLE$$;$$ARRAY_UNIQ$$')
    source = sources(:one)
    source.update!(algorithm_value: "  $$META_TITLE$$ \n; ruby=[\"$$META_TITLE$$\"];$$TITLE_BLOCK$$;")
    entry.update!(name: "OPEN_GRAPH_TITLE")
    assert_equal "  $$OPEN_GRAPH_TITLE$$ \n; ruby=[\"$$META_TITLE$$\"];$$TITLE_BLOCK$$;", source.reload.algorithm_value
    assert_equal '$$OPEN_GRAPH_TITLE$$;$$ARRAY_UNIQ$$', nested.reload.body
    assert_equal ["META_TITLE"], entry.aliases
    assert_equal 2, entry.revision
    assert_equal 2, nested.revision
    assert_equal '$$META_TITLE$$;$$ARRAY_UNIQ$$', nested.versions.find_by!(revision: 1).body
    assert_equal "OPEN_GRAPH_TITLE", entry.versions.find_by!(revision: 2).name
    assert_equal Dsl::LibraryExpander.call('$$OPEN_GRAPH_TITLE$$')[:steps], Dsl::LibraryExpander.call('$$META_TITLE$$')[:steps]
    assert_includes entry.references, source
  end

  test "collisions including previous names and reserved SELF_URL cannot rename or change references" do
    entry = DslLibraryEntry.find_by!(name: "META_TITLE")
    entry.update!(name: "OPEN_GRAPH_TITLE")
    other = DslLibraryEntry.find_by!(name: "HTML_TITLE")
    ["META_TITLE", "OPEN_GRAPH_TITLE", "SELF_URL"].each do |name|
      assert_not other.update(name: name)
      other.reload
      assert_equal "HTML_TITLE", other.name
    end
    entry.update!(name: "META_TITLE")
    assert_equal ["OPEN_GRAPH_TITLE"], entry.aliases
  end

  test "reference update failures roll back the entire rename" do
    entry = DslLibraryEntry.find_by!(name: "META_TITLE")
    source = sources(:one)
    source.update!(algorithm_value: '$$META_TITLE$$')
    Source.any_instance.stubs(:update!).raises(ActiveRecord::RecordInvalid.new(Source.new))
    assert_raises(ActiveRecord::RecordInvalid) { entry.update!(name: "RENAMED_TITLE") }
    assert_equal "META_TITLE", entry.reload.name
    assert_equal 1, entry.revision
    assert_empty entry.aliases
    assert_equal '$$META_TITLE$$', source.reload.algorithm_value
  end

  test "an old alias in a newly imported source resolves after multiple renames" do
    entry = DslLibraryEntry.find_by!(name: "META_TITLE")
    entry.update!(name: "OPEN_GRAPH_TITLE")
    source = sources(:one)
    source.update!(algorithm_value: '$$META_TITLE$$')
    entry.update!(name: "PAGE_META_TITLE")
    assert_includes entry.references, source
    assert_equal Dsl::LibraryExpander.call('$$PAGE_META_TITLE$$')[:steps], Dsl::LibraryExpander.call(source.reload.algorithm_value)[:steps]
    assert_equal ["META_TITLE", "OPEN_GRAPH_TITLE"], entry.aliases
  end

end
