class AddShowProjectProgressToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :show_project_progress, :boolean, default: true, null: false
  end
end
