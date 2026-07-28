class CreateLogEntries < ActiveRecord::Migration[7.2]
  def change
    create_table :log_entries do |t|
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :log_entry_type, null: false, foreign_key: true
      t.text :body, null: false

      t.timestamps
    end
  end
end
