class CreateStageTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :stage_templates do |t|
      t.references :project_type, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end
