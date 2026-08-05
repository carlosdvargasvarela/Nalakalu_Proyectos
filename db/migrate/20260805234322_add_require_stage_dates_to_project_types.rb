class AddRequireStageDatesToProjectTypes < ActiveRecord::Migration[7.2]
  def change
    add_column :project_types, :require_stage_dates, :boolean, default: false, null: false
  end
end
