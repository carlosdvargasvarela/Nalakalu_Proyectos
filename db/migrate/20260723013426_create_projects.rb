class CreateProjects < ActiveRecord::Migration[7.2]
  def change
    create_table :projects do |t|
      t.references :project_type, null: false, foreign_key: true
      t.string :name, null: false
      t.jsonb :custom_fields, null: false, default: {}
      t.string :status, null: false, default: "active"

      t.timestamps
    end
  end
end
