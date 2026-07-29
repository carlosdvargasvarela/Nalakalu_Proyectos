class CreateResponsibleTypes < ActiveRecord::Migration[7.2]
  def change
    create_table :responsible_types do |t|
      t.references :project_type, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
      t.index [:project_type_id, :name], unique: true
    end
  end
end
