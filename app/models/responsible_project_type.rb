class ResponsibleProjectType < ApplicationRecord
  belongs_to :responsible
  belongs_to :project_type

  validates :responsible_id, uniqueness: { scope: :project_type_id }
end
