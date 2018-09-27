class AddIndexToWebpages < ActiveRecord::Migration[5.1]
  def change
    add_index :webpages, :url
    add_index :webpages, [:url, :website_id], unique: :true
  end
end
