class RemoveNextStepFromSource < ActiveRecord::Migration[5.2]
  def change
    remove_column :sources, :next_step
  end
end
