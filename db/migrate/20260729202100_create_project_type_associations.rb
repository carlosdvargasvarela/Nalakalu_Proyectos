class CreateProjectTypeAssociations < ActiveRecord::Migration[7.2]
  def change
    create_table :project_type_associations do |t|
      t.references :from_project_type, null: false, foreign_key: { to_table: :project_types }
      t.references :to_project_type, null: false, foreign_key: { to_table: :project_types }
      t.string :label, null: false
      t.boolean :responsables_can_create, default: false, null: false
      t.timestamps
    end
  end
end
