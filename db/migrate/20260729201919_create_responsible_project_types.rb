class CreateResponsibleProjectTypes < ActiveRecord::Migration[7.2]
  def change
    create_table :responsible_project_types do |t|
      t.references :responsible, null: false, foreign_key: true
      t.references :project_type, null: false, foreign_key: true
      t.timestamps
      t.index [:responsible_id, :project_type_id], unique: true, name: "index_responsible_project_types_on_pair"
    end
  end
end
