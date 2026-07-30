class MigrateInstallersToResponsibles < ActiveRecord::Migration[7.2]
  # ponytail: a migration must stay runnable forever against a fresh database,
  # even after the app's own Installer model is deleted (which happens later
  # in this same migration sequence's history) — so it defines its own
  # throwaway model scoped to the migration instead of depending on
  # app/models/installer.rb, which no longer exists.
  class MigrationInstaller < ActiveRecord::Base
    self.table_name = "installers"
  end

  def up
    installer_fields = FieldDefinition.where(reference_table: "installers")
    return if installer_fields.none?

    responsible_type_by_project_type = installer_fields.pluck(:project_type_id).uniq.index_with do |pt_id|
      ResponsibleType.create!(project_type_id: pt_id, name: "Instalador")
    end

    installer_to_responsible = MigrationInstaller.all.to_h do |installer|
      [installer.id, Responsible.create!(name: installer.name, color: installer.color)]
    end

    installer_fields.each do |field|
      responsible_type = responsible_type_by_project_type[field.project_type_id]
      Project.where(project_type_id: field.project_type_id).find_each do |project|
        installer_id = project.custom_fields[field.key]
        next if installer_id.blank?
        responsible = installer_to_responsible[installer_id.to_i]
        next if responsible.nil?
        ProjectResponsible.create!(project: project, responsible: responsible, responsible_type: responsible_type)
      end
    end

    installer_fields.destroy_all
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
