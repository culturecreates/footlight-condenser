class AddTransitionCheckRequestedAtToWebsites < ActiveRecord::Migration[8.0]
  def change
    add_column :websites, :transition_check_requested_at, :datetime
    add_index :websites, :transition_check_requested_at
  end
end
