class ProjectStage < ApplicationRecord
  belongs_to :project
  belongs_to :stage_template, optional: true

  validates :name, presence: true
end
