class AddResponsibleTypeToResponsibleProjectTypes < ActiveRecord::Migration[7.2]
  # ponytail: throwaway table-only model, see 20260729183056 for why real
  # models can't be used inside a migration.
  class MigrationResponsibleProjectType < ActiveRecord::Base
    self.table_name = "responsible_project_types"
  end

  def up
    add_reference :responsible_project_types, :responsible_type, null: true, foreign_key: true

    MigrationResponsibleProjectType.reset_column_information
    MigrationResponsibleProjectType.find_each do |rpt|
      responsible_type_id = execute(
        "SELECT id FROM responsible_types WHERE project_type_id = #{rpt.project_type_id.to_i} ORDER BY id LIMIT 1"
      ).first&.fetch("id")
      rpt.update_column(:responsible_type_id, responsible_type_id) if responsible_type_id
    end
  end

  def down
    remove_reference :responsible_project_types, :responsible_type, foreign_key: true
  end
end
