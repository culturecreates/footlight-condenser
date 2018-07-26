class CreateWebpages < ActiveRecord::Migration[5.1]
  def change
    create_table :webpages do |t|
      t.string :url
      t.string :language
      t.string :rdf_uri
      t.references :rdfs_class, foreign_key: true
      t.references :website, foreign_key: true

      t.timestamps
    end
  end
end
