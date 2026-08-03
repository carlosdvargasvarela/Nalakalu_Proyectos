class Responsible < ApplicationRecord
  belongs_to :user, optional: true
  has_many :project_responsibles, dependent: :nullify
  has_many :responsible_project_types, dependent: :destroy
  has_many :project_types, through: :responsible_project_types

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
  validates :user_id, uniqueness: true, allow_nil: true

  after_update :resync_project_responsibles_snapshot, if: -> { saved_change_to_name? || saved_change_to_color? }

  private

  def resync_project_responsibles_snapshot
    project_responsibles.update_all(responsible_name: name, responsible_color: color)
  end
end
