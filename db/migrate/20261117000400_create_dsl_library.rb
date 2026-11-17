class CreateDslLibrary < ActiveRecord::Migration[8.0]
  def up
    create_table :dsl_library_entries do |t|
      t.string :name, null: false
      t.text :body, null: false
      t.text :description
      t.integer :revision, default: 1, null: false
      t.integer :lock_version, default: 0, null: false
      t.timestamps
    end
    add_index :dsl_library_entries, :name, unique: true
    create_table :dsl_library_versions do |t|
      t.references :dsl_library_entry, null: false, foreign_key: true
      t.integer :revision, null: false
      t.text :body, null: false
      t.timestamps
    end
    add_index :dsl_library_versions, [:dsl_library_entry_id, :revision], unique: true
    entries = JSON.parse(<<~'JSON')
[["META_TITLE", "xpath=//meta[@property='og:title']/@content", "Append Open Graph title matches; does not clear prior results."], ["META_IMAGE", "xpath=//meta[@property='og:image']/@content", "Append Open Graph image URLs."], ["META_DESCRIPTION", "xpath=//meta[@property='og:description']/@content", "Append Open Graph descriptions."], ["HTML_TITLE", "xpath=//title", "Append document title matches."], ["JSON_LD_SCRIPTS", "xpath=//script[@type='application/ld+json']", "Append script text only; no assumption about JSON object, array or @graph shape."], ["CURRENT_URL", "ruby=$url", "Replace results with the current URL string."], ["ARRAY_UNIQ", "ruby=$array.uniq", "Remove duplicate values, preserving order and nested value types."], ["ARRAY_SQUISH", "ruby=$array.map{|e| e.squish}", "Normalize whitespace on string elements. Requires an array of strings."], ["ARRAY_SAVE", "ruby=[$array]", "Preserve current state as one nested element before more accumulating extraction."], ["ARRAY_DROP_FIRST", "ruby=$array.drop(1)", "Remove the first outer element; distinct from ARRAY_FIRST."], ["ARRAY_FIRST", "ruby=$array.size > 1 ? $array.drop(1).map{|e| e.squish} : $array", "Operator-supplied instruction: drop the saved first element only when size > 1, then squish remaining strings. Does NOT mean return .first."]]
    JSON
    entries.each do |name, body, description|
      execute "INSERT INTO dsl_library_entries (name, body, description, created_at, updated_at) VALUES (#{connection.quote(name)}, #{connection.quote(body)}, #{connection.quote(description)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
    end
    execute "INSERT INTO dsl_library_versions (dsl_library_entry_id, revision, body, created_at, updated_at) SELECT id, revision, body, created_at, updated_at FROM dsl_library_entries"
  end

  def down
    drop_table :dsl_library_versions
    drop_table :dsl_library_entries
  end
end
