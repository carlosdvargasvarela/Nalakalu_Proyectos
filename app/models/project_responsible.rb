class ProjectResponsible < ApplicationRecord
  belongs_to :project
  belongs_to :responsible
  belongs_to :responsible_type
  belongs_to :project_stage, optional: true

  validates :responsible_id, uniqueness: { scope: [:project_id, :responsible_type_id, :project_stage_id] }
  validate :project_stage_belongs_to_project
  validate :responsible_type_belongs_to_project_type
  validate :responsible_enabled_for_project_type

  def project_wide?
    project_stage_id.nil?
  end

  private

  def project_stage_belongs_to_project
    return if project_stage.nil? || project.nil?
    errors.add(:project_stage, "debe pertenecer al mismo proyecto") unless project_stage.project_id == project.id
  end

  def responsible_type_belongs_to_project_type
    return if responsible_type.nil? || project.nil?
    errors.add(:responsible_type, "debe pertenecer al tipo de este proyecto") unless responsible_type.project_type_id == project.project_type_id
  end

  def responsible_enabled_for_project_type
    return if responsible.nil? || project.nil?
    errors.add(:responsible, "no está habilitado para este tipo de proyecto") unless responsible.project_types.include?(project.project_type)
  end
end
