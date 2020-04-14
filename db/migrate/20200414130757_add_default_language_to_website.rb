class AddDefaultLanguageToWebsite < ActiveRecord::Migration[5.1]
  def change
    add_column :websites, :default_language, :string, :default => "en"
  end
end
