class AddResponsibleSnapshotToProjectResponsibles < ActiveRecord::Migration[7.2]
  def up
    add_column :project_responsibles, :responsible_name, :string
    add_column :project_responsibles, :responsible_color, :string
    change_column_null :project_responsibles, :responsible_id, true

    execute <<~SQL
      UPDATE project_responsibles
      SET responsible_name = responsibles.name, responsible_color = responsibles.color
      FROM responsibles
      WHERE project_responsibles.responsible_id = responsibles.id
    SQL

    change_column_null :project_responsibles, :responsible_name, false
    change_column_null :project_responsibles, :responsible_color, false
  end

  def down
    change_column_null :project_responsibles, :responsible_id, false
    remove_column :project_responsibles, :responsible_color
    remove_column :project_responsibles, :responsible_name
  end
end
