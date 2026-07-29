class ProjectTypeAccess < ApplicationRecord
  belongs_to :user
  belongs_to :project_type

  validates :user_id, uniqueness: { scope: :project_type_id }
end
