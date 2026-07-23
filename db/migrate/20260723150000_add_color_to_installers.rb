class AddColorToInstallers < ActiveRecord::Migration[7.2]
  def change
    add_column :installers, :color, :string, null: false, default: "#6c757d"
  end
end
