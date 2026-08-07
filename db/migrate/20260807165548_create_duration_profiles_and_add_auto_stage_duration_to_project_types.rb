class CreateDurationProfilesAndAddAutoStageDurationToProjectTypes < ActiveRecord::Migration[7.2]
  def change
    add_column :project_types, :auto_stage_duration_enabled, :boolean, default: false, null: false
    add_reference :project_types, :duration_reference_field_definition, foreign_key: { to_table: :field_definitions }, null: true

    create_table :duration_profiles do |t|
      t.references :project_type, null: false, foreign_key: true
      t.string :operator, null: false
      t.decimal :min_value
      t.decimal :max_value
      t.integer :position, default: 0, null: false
      t.jsonb :durations, default: {}, null: false
      t.timestamps
    end
  end
end
