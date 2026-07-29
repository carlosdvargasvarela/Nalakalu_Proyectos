class Responsible < ApplicationRecord
  belongs_to :user, optional: true
  has_many :project_responsibles, dependent: :destroy
  has_many :responsible_project_types, dependent: :destroy
  has_many :project_types, through: :responsible_project_types

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
  validates :user_id, uniqueness: true, allow_nil: true
end
