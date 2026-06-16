class AddDistillatorReportingIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :websites, :distillator_mode unless index_exists?(:websites, :distillator_mode)
    add_index :distillator_fetch_caches, :normalized_url unless index_exists?(:distillator_fetch_caches, :normalized_url)
  end
end
