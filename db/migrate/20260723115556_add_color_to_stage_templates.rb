class AddColorToStageTemplates < ActiveRecord::Migration[7.2]
  def change
    add_column :stage_templates, :color, :string, null: false, default: "#6c757d"
  end
end
