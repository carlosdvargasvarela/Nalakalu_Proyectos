class MigrateInstallersToResponsibles < ActiveRecord::Migration[7.2]
  # ponytail: a migration must stay runnable forever against a fresh database,
  # replayed top-to-bottom against the CURRENT app code. Any of the app's real
  # models — even ones that still exist today — can be unsafe to call .create!
  # on from here: a later migration in this same sequence adds a validation
  # (responsible_enabled_for_project_type, which queries the
  # responsible_project_types table) that doesn't exist yet at this point in
  # migration history, so the live ProjectResponsible model would blow up with
  # "relation does not exist" on a fresh install. Throwaway table-only models
  # (no validations, no callbacks, immune to every future change to the real
  # models) sidestep this permanently — this bit the Installer constant once
  # already (fixed in a previous commit) and then bit ProjectResponsible's
  # validation the same way, so all four models this migration touches are
  # scoped here now, not just the one that happened to fail first.
  class MigrationInstaller < ActiveRecord::Base
    self.table_name = "installers"
  end

  class MigrationResponsibleType < ActiveRecord::Base
    self.table_name = "responsible_types"
  end

  class MigrationResponsible < ActiveRecord::Base
    self.table_name = "responsibles"
  end

  class MigrationProjectResponsible < ActiveRecord::Base
    self.table_name = "project_responsibles"
  end

  def up
    installer_fields = FieldDefinition.where(reference_table: "installers")
    return if installer_fields.none?

    responsible_type_id_by_project_type = installer_fields.pluck(:project_type_id).uniq.index_with do |pt_id|
      MigrationResponsibleType.create!(project_type_id: pt_id, name: "Instalador").id
    end

    installer_to_responsible_id = MigrationInstaller.all.to_h do |installer|
      [installer.id, MigrationResponsible.create!(name: installer.name, color: installer.color).id]
    end

    installer_fields.each do |field|
      responsible_type_id = responsible_type_id_by_project_type[field.project_type_id]
      Project.where(project_type_id: field.project_type_id).find_each do |project|
        installer_id = project.custom_fields[field.key]
        next if installer_id.blank?
        responsible_id = installer_to_responsible_id[installer_id.to_i]
        next if responsible_id.nil?
        MigrationProjectResponsible.create!(project_id: project.id, responsible_id: responsible_id, responsible_type_id: responsible_type_id)
      end
    end

    installer_fields.destroy_all
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
