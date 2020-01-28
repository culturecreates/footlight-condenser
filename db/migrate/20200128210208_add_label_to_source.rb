class AddLabelToSource < ActiveRecord::Migration[5.1]
  def change
    add_column :sources, :label, :string
  end
end
