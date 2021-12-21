class AddSelectedIndividualToStatement < ActiveRecord::Migration[5.2]
  def change
    add_column :statements, :selected_individual, :boolean, default: false
    selected_statements = Statement.includes(:source).where(sources: {selected: true})
    selected_statements.update_all(selected_individual: true)
  end
end
