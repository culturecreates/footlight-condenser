class AddDistillatorModeToWebsites < ActiveRecord::Migration[8.0]
  def change
    add_column :websites, :distillator_mode, :string, null: false, default: "legacy"
  end
end
