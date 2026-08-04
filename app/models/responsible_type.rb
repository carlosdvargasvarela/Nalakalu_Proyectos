class ResponsibleType < ApplicationRecord
  belongs_to :project_type
  has_many :project_responsibles, dependent: :destroy
  has_many :responsible_project_types, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :project_type_id }

  before_save :clear_other_defaults, if: :default_in_filter?

  private

  def clear_other_defaults
    project_type.responsible_types.where.not(id: id).update_all(default_in_filter: false)
  end
end
