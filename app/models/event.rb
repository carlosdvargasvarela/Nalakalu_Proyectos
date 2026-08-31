class Event < ApplicationRecord
  belongs_to :project
  belongs_to :project_stage, optional: true
  belongs_to :event_type
  belongs_to :responsible, optional: true

  validates :title, presence: true
  validates :event_date, presence: true
  validates :status, inclusion: { in: %w[pendiente realizado] }
  validate :project_stage_belongs_to_project
  validate :event_type_belongs_to_project_type

  def project_wide?
    project_stage_id.nil?
  end

  private

  def project_stage_belongs_to_project
    return if project_stage.nil? || project.nil?
    errors.add(:project_stage, "debe pertenecer al mismo proyecto") unless project_stage.project_id == project.id
  end

  def event_type_belongs_to_project_type
    return if event_type.nil? || project.nil?
    errors.add(:event_type, "debe pertenecer al tipo de este proyecto") unless event_type.project_type_id == project.project_type_id
  end
end
