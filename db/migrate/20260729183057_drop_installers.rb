class DropInstallers < ActiveRecord::Migration[7.2]
  def change
    drop_table :installers do |t|
      t.string :name, null: false
      t.string :color, default: "#6c757d", null: false
      t.timestamps
    end
  end
end
