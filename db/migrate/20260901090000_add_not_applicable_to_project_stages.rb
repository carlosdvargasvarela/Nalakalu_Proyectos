class AddNotApplicableToProjectStages < ActiveRecord::Migration[7.2]
  def change
    add_column :project_stages, :not_applicable, :boolean, default: false, null: false
  end
end
