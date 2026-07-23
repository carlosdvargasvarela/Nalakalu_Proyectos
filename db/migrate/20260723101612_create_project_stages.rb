class CreateProjectStages < ActiveRecord::Migration[7.2]
  def change
    create_table :project_stages do |t|
      t.references :project, null: false, foreign_key: true
      t.references :stage_template, null: true, foreign_key: { on_delete: :nullify }
      t.string :name, null: false
      t.date :start_date
      t.date :end_date
      t.integer :progress_percent, null: false, default: 0
      t.integer :assigned_user_id

      t.timestamps
    end
  end
end
