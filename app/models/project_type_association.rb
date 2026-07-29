class ProjectTypeAssociation < ApplicationRecord
  belongs_to :from_project_type, class_name: "ProjectType"
  belongs_to :to_project_type, class_name: "ProjectType"
  has_many :project_associations, dependent: :destroy

  validates :label, presence: true
end
