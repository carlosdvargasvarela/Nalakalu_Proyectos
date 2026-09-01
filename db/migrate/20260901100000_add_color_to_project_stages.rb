class AddColorToProjectStages < ActiveRecord::Migration[7.2]
  def change
    add_column :project_stages, :color, :string, default: "#6c757d", null: false
  end
end
