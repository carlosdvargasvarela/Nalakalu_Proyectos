class CreateFieldDefinitions < ActiveRecord::Migration[7.2]
  def change
    create_table :field_definitions do |t|
      t.references :project_type, null: false, foreign_key: true
      t.string :key, null: false
      t.string :label, null: false
      t.string :data_type, null: false
      t.string :reference_table
      t.integer :position, null: false, default: 0
      t.boolean :show_in_gantt, null: false, default: false
      t.timestamps
    end
    add_index :field_definitions, [:project_type_id, :key], unique: true
  end
end
