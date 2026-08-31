class AddIconToProjectTypes < ActiveRecord::Migration[7.2]
  def change
    add_column :project_types, :icon, :string, default: "bi-kanban", null: false
  end
end
