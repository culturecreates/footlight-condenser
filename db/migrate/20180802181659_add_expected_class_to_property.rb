class AddExpectedClassToProperty < ActiveRecord::Migration[5.1]
  def change
    add_column :properties, :expected_class, :string
  end
end
