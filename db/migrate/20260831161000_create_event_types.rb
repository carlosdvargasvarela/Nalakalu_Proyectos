class CreateEventTypes < ActiveRecord::Migration[7.2]
  def change
    create_table :event_types do |t|
      t.references :project_type, null: false, foreign_key: true
      t.string :name, null: false
      t.string :color, null: false, default: "#6c757d"
      t.string :icon, null: false, default: "bi-calendar-event"
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
