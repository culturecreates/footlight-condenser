require "test_helper"

class DslLibraryEntriesControllerTest < ActionDispatch::IntegrationTest
  test "SELF_URL shows the actual normalized app origin separately from editable instructions" do
    original = ENV["CONDENSER_PUBLIC_URL"]
    ENV["CONDENSER_PUBLIC_URL"] = "https://footlight-condenser-test-c24c162bb7c8.herokuapp.com/"
    Distillator::FetchService.expects(:fetch).never
    assert_no_difference "DslLibraryEntry.count" do
      get dsl_library_entries_path
    end
    assert_response :success
    assert_select "#dsl-url-placeholders code", text: '$$SELF_URL$$'
    assert_select "#dsl-url-placeholders code", text: "https://footlight-condenser-test-c24c162bb7c8.herokuapp.com"
    assert_select "#dsl-url-placeholders pre", text: 'api="$$SELF_URL$$/statements.json?source=8039&seedurl=culturemauricie_lepointdevente-com-RList"'
    shorthand = DslLibraryEntry.find_by!(name: "CURRENT_URL")
    assert_select "details:not([open]) a[href='#{edit_dsl_library_entry_path(shorthand)}']", count: 1
  ensure
    ENV["CONDENSER_PUBLIC_URL"] = original
  end

  test "invalid origin displays an actionable warning without breaking the library" do
    Dsl::Support::UrlPlaceholders.expects(:expand).with('$$SELF_URL$$').raises(ArgumentError, "CONDENSER_PUBLIC_URL is invalid")
    get dsl_library_entries_path
    assert_response :success
    assert_select "#dsl-url-placeholders [role=alert]", text: "CONDENSER_PUBLIC_URL is invalid"
  end

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
  test "token name is editable and saving a rename updates referencing sources" do
    entry = DslLibraryEntry.find_by!(name: "META_TITLE")
    source = sources(:one)
    source.update!(algorithm_value: '$$META_TITLE$$')
    get edit_dsl_library_entry_path(entry)
    assert_select "input[name='dsl_library_entry[name]'][readonly]", count: 0
    patch dsl_library_entry_path(entry), params: {dsl_library_entry: {name: "OPEN_GRAPH_TITLE", lock_version: entry.lock_version}}
    assert_redirected_to edit_dsl_library_entry_path(entry)
    assert_equal '$$OPEN_GRAPH_TITLE$$', source.reload.algorithm_value
    assert_equal "OPEN_GRAPH_TITLE", entry.reload.name
  end

  test "failed source rewrite returns an operator error and leaves the old token intact" do
    entry = DslLibraryEntry.find_by!(name: "META_TITLE")
    source = sources(:one)
    source.update!(algorithm_value: '$$META_TITLE$$')
    Source.any_instance.stubs(:update!).raises(ActiveRecord::RecordInvalid.new(Source.new))
    patch dsl_library_entry_path(entry), params: {dsl_library_entry: {name: "OPEN_GRAPH_TITLE", lock_version: entry.lock_version}}
    assert_response :unprocessable_entity
    assert_includes response.body, "No changes saved"
    assert_equal "META_TITLE", entry.reload.name
    assert_equal '$$META_TITLE$$', source.reload.algorithm_value
  end

end
