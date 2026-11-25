class AddFetchProvenanceToStatements < ActiveRecord::Migration[8.0]
  def change
    add_column :statements, :fetch_provenance, :jsonb, default: {}, null: false
  end
end
