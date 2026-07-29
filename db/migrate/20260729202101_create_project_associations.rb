class CreateProjectAssociations < ActiveRecord::Migration[7.2]
  def change
    create_table :project_associations do |t|
      t.references :from_project, null: false, foreign_key: { to_table: :projects }
      t.references :to_project, null: false, foreign_key: { to_table: :projects }
      t.references :project_type_association, null: false, foreign_key: true
      t.timestamps
      t.index [:from_project_id, :to_project_id, :project_type_association_id], unique: true, name: "index_project_associations_on_triple"
    end
  end
end
