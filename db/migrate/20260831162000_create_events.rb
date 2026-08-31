class CreateEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :events do |t|
      t.references :project, null: false, foreign_key: true
      t.references :project_stage, foreign_key: true
      t.references :event_type, null: false, foreign_key: true
      t.references :responsible, foreign_key: true
      t.string :title, null: false
      t.date :event_date, null: false
      t.time :event_time
      t.text :notes
      t.string :status, null: false, default: "pendiente"

      t.timestamps
    end
  end
end
