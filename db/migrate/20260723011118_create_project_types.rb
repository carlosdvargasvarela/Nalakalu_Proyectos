class CreateProjectTypes < ActiveRecord::Migration[7.2]
  def change
    create_table :project_types do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
    end
    add_index :project_types, :slug, unique: true
  end
end
