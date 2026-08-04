class ResponsibleProjectType < ApplicationRecord
  belongs_to :responsible
  belongs_to :project_type
  belongs_to :responsible_type

  validates :responsible_id, uniqueness: { scope: :project_type_id }
  validate :responsible_type_belongs_to_project_type

  private

  def responsible_type_belongs_to_project_type
    return if responsible_type.nil? || project_type.nil?
    errors.add(:responsible_type, "debe pertenecer a este tipo de proyecto") unless responsible_type.project_type_id == project_type_id
  end
end
