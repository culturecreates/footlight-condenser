class AddCancelRequestedAtToDistillatorSiteTransitions < ActiveRecord::Migration[8.0]
  def change
    add_column :distillator_site_transitions, :cancel_requested_at, :datetime
  end
end
