class AddDiscoveryTargetToWebpages < ActiveRecord::Migration[8.0]
  def change
    add_reference :webpages, :discovery_target_website, foreign_key: { to_table: :websites }
  end
end
