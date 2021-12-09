class AddSelectedIndividualToStatement < ActiveRecord::Migration[5.2]
  def change
    add_column :statements, :selected_individual, :boolean, default: false
  end
end
