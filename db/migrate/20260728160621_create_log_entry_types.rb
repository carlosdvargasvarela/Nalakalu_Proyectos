class CreateLogEntryTypes < ActiveRecord::Migration[7.2]
  def change
    create_table :log_entry_types do |t|
      t.references :project_type, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: "#6c757d"

      t.timestamps
    end
  end
end
