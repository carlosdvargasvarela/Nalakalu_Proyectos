class ResponsibleType < ApplicationRecord
  belongs_to :project_type
  has_many :project_responsibles, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :project_type_id }
end
