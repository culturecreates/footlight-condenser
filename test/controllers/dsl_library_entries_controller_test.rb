require "test_helper"

class DslLibraryEntriesControllerTest < ActionDispatch::IntegrationTest
  test "navigation library and editable seeded entries are visible" do
    get dsl_library_entries_path
    assert_response :success
    assert_includes response.body, "$$META_TITLE$$"
    assert_select "a[href='#{dsl_library_entries_path}']", minimum: 1
    get edit_dsl_library_entry_path(DslLibraryEntry.find_by!(name: "ARRAY_FIRST"))
    assert_response :success
    assert_includes response.body, "Revision history"
    assert_includes response.body, "drop(1)"
  end

  test "operator creates a multi-step block and spelling errors are rejected" do
    post dsl_library_entries_path, params: { dsl_library_entry: {name: "CUSTOM_PIPELINE", body: '$$META_TITLE$$;$$ARRAY_UNIQ$$'} }
    entry = DslLibraryEntry.find_by!(name: "CUSTOM_PIPELINE")
    assert_redirected_to edit_dsl_library_entry_path(entry)
    patch dsl_library_entry_path(entry), params: {dsl_library_entry: {body: '$$META_TITEL$$', lock_version: entry.lock_version}}
    assert_response :unprocessable_entity
    assert_includes response.body, "META_TITEL"
    assert_equal 1, entry.reload.revision
  end

  test "concurrent form submission returns conflict without overwriting" do
    entry = DslLibraryEntry.find_by!(name: "HTML_TITLE")
    old_version = entry.lock_version
    entry.update!(body: 'xpath=//h1')
    patch dsl_library_entry_path(entry), params: {dsl_library_entry: {body: 'xpath=//p', lock_version: old_version}}
    assert_response :conflict
    assert_equal 'xpath=//h1', entry.reload.body
  end
end
