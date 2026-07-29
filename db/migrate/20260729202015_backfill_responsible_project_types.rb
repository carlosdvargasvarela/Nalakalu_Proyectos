class BackfillResponsibleProjectTypes < ActiveRecord::Migration[7.2]
  def up
    ProjectResponsible.includes(:responsible, project: :project_type).find_each do |pr|
      ResponsibleProjectType.find_or_create_by!(responsible_id: pr.responsible_id, project_type_id: pr.project.project_type_id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
