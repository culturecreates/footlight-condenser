class ShortenDslArrayTokenNames < ActiveRecord::Migration[8.0]
  def up
    # Use the normal rename contract: aliases, revisions and atomic reference
    # updates. Preserve environment-local bodies, including reviewed edits.
    DslLibraryEntry.shorten_array_names!
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Token renames retain compatible aliases; use the library editor to rename without discarding later operator edits."
  end
end
