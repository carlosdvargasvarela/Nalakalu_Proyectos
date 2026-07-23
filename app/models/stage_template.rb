class StageTemplate < ApplicationRecord
  belongs_to :project_type

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }

  before_save :clear_other_defaults, if: :default_in_filter?

  private

  def clear_other_defaults
    project_type.stage_templates.where.not(id: id).update_all(default_in_filter: false)
  end
end
