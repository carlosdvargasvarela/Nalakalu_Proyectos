class ProjectAssociation < ApplicationRecord
  belongs_to :from_project, class_name: "Project"
  belongs_to :to_project, class_name: "Project"
  belongs_to :project_type_association

  validate :projects_match_association_types
  validate :from_and_to_are_different

  private

  def projects_match_association_types
    return if from_project.nil? || to_project.nil? || project_type_association.nil?
    errors.add(:from_project, "debe ser del tipo esperado por la asociación") unless from_project.project_type_id == project_type_association.from_project_type_id
    errors.add(:to_project, "debe ser del tipo esperado por la asociación") unless to_project.project_type_id == project_type_association.to_project_type_id
  end

  def from_and_to_are_different
    errors.add(:to_project, "un proyecto no puede asociarse consigo mismo") if from_project_id.present? && from_project_id == to_project_id
  end
end
