class AddDslLibraryRenameHistory < ActiveRecord::Migration[8.0]
  def change
    add_column :dsl_library_entries, :aliases, :jsonb, default: [], null: false
    add_column :dsl_library_versions, :name, :string
    reversible do |direction|
      direction.up do
        execute "UPDATE dsl_library_versions v SET name = e.name FROM dsl_library_entries e WHERE v.dsl_library_entry_id = e.id"
      end
    end
  end
end
