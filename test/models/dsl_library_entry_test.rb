require "test_helper"

class DslLibraryEntryTest < ActiveSupport::TestCase
  test "array prefix migration preserves bodies aliases history and complete references" do
    originals = DslLibraryEntry.where("name LIKE 'ARRAY_%'").to_a
    expected = {"ARRAY_UNIQ" => "A_UNIQ", "ARRAY_SQUISH" => "A_SQUISH", "ARRAY_SAVE" => "A_SAVE",
      "ARRAY_DROP_FIRST" => "A_DROP_FIRST_ALWAYS", "ARRAY_FIRST" => "A_DROP_FIRST"}
    nested = DslLibraryEntry.create!(name: "SAVED_ARRAY", body: '$$ARRAY_SAVE$$;$$ARRAY_UNIQ$$')
    source = sources(:one)
    source.update!(algorithm_value: " $$ARRAY_UNIQ$$ ;$$ARRAY_FIRST$$;ruby=['$$ARRAY_SAVE$$']")
    bodies = originals.to_h { |entry| [entry.id, entry.body] }
    require Rails.root.join("db/migrate/20261117000600_shorten_dsl_array_token_names")
    ShortenDslArrayTokenNames.new.up
    originals.each do |entry|
      old_name = entry.name
      entry.reload
      assert_equal expected.fetch(old_name), entry.name
      assert_equal bodies.fetch(entry.id), entry.body
      assert_includes entry.aliases, old_name
      assert_equal bodies.fetch(entry.id), entry.versions.find_by!(revision: 1).body
      assert_equal Dsl::LibraryExpander.call("$$#{entry.name}$$")[:steps], Dsl::LibraryExpander.call("$$#{old_name}$$")[:steps]
    end
    assert_equal '$$A_SAVE$$;$$A_UNIQ$$', nested.reload.body
    assert_equal " $$A_UNIQ$$ ;$$A_DROP_FIRST$$;ruby=['$$ARRAY_SAVE$$']", source.reload.algorithm_value
    assert_empty DslLibraryEntry.shorten_array_names!
  end

  test "already renamed conditional drop keeps its reviewed body and revision" do
    conditional = DslLibraryEntry.find_by!(name: "ARRAY_FIRST")
    reviewed = 'ruby=$array.is_a?(Array) && $array.size > 1 ? $array.drop(1).map{|e| e.squish} : $array'
    conditional.update!(name: "A_DROP_FIRST", body: reviewed)
    revision = conditional.revision
    DslLibraryEntry.shorten_array_names!
    assert_equal reviewed, conditional.reload.body
    assert_equal revision, conditional.revision
    assert_equal 'ruby=$array.drop(1)', DslLibraryEntry.find_by!(name: "A_DROP_FIRST_ALWAYS").body
    assert_includes conditional.aliases, "ARRAY_FIRST"
  end

  test "a conflicting short name rolls back every array rename and reference update" do
    candidates = DslLibraryEntry.order(:id).select { |entry| entry.name.start_with?("ARRAY_") }
    last = candidates.last
    conflict = {"ARRAY_FIRST" => "A_DROP_FIRST", "ARRAY_DROP_FIRST" => "A_DROP_FIRST_ALWAYS"}.fetch(last.name) { last.name.sub(/\AARRAY_/, "A_") }
    DslLibraryEntry.create!(name: conflict, body: 'ruby=[]')
    before = candidates.to_h { |entry| [entry.id, entry.attributes] }
    versions = DslLibraryVersion.count
    source = sources(:one)
    source.update!(algorithm_value: '$$ARRAY_UNIQ$$;$$ARRAY_SAVE$$')
    assert_raises(ActiveRecord::RecordInvalid) { DslLibraryEntry.shorten_array_names! }
    candidates.each { |entry| assert_equal before.fetch(entry.id), entry.reload.attributes }
    assert_equal versions, DslLibraryVersion.count
    assert_equal '$$ARRAY_UNIQ$$;$$ARRAY_SAVE$$', source.reload.algorithm_value
  end

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
