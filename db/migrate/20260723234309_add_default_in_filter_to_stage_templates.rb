class AddDefaultInFilterToStageTemplates < ActiveRecord::Migration[7.2]
  def change
    add_column :stage_templates, :default_in_filter, :boolean, default: false, null: false
  end
end
