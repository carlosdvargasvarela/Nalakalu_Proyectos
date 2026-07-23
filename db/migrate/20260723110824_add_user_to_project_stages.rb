class AddUserToProjectStages < ActiveRecord::Migration[7.2]
  def change
    add_reference :project_stages, :user, null: true, foreign_key: true
    remove_column :project_stages, :assigned_user_id, :integer
  end
end
