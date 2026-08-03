class AddDefaultInFilterToResponsibleTypes < ActiveRecord::Migration[7.2]
  def change
    add_column :responsible_types, :default_in_filter, :boolean, default: false, null: false
  end
end
