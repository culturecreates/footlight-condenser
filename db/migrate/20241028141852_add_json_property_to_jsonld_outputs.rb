class AddJsonPropertyToJsonldOutputs < ActiveRecord::Migration[5.2]
  def change
    add_column :jsonld_outputs, :frame, :json
  end
end
