class CreateProjectTypeAccesses < ActiveRecord::Migration[7.2]
  def change
    create_table :project_type_accesses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :project_type, null: false, foreign_key: true
      t.boolean :can_edit, null: false, default: false

      t.timestamps

      t.index [:user_id, :project_type_id], unique: true
    end
  end
end
