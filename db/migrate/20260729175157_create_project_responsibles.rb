class CreateProjectResponsibles < ActiveRecord::Migration[7.2]
  def change
    create_table :project_responsibles do |t|
      t.references :project, null: false, foreign_key: true
      t.references :responsible, null: false, foreign_key: true
      t.references :responsible_type, null: false, foreign_key: true
      t.references :project_stage, null: true, foreign_key: true
      t.timestamps
      t.index [:project_id, :responsible_id, :responsible_type_id, :project_stage_id],
        unique: true, name: "index_project_responsibles_on_assignment"
    end
  end
end
