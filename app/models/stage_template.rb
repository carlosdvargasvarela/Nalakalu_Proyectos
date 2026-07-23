class StageTemplate < ApplicationRecord
  belongs_to :project_type

  validates :name, presence: true
end
