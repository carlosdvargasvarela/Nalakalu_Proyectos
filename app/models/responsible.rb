class Responsible < ApplicationRecord
  belongs_to :user, optional: true
  has_many :project_responsibles, dependent: :nullify
  has_many :events, dependent: :nullify
  has_many :responsible_project_types, dependent: :destroy
  has_many :project_types, through: :responsible_project_types

  accepts_nested_attributes_for :responsible_project_types, allow_destroy: true,
    reject_if: proc { |attrs| attrs["responsible_type_id"].blank? && attrs["id"].blank? }

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
  validates :user_id, uniqueness: true, allow_nil: true

  after_update :resync_project_responsibles_snapshot, if: -> { saved_change_to_name? || saved_change_to_color? }

  # A row with responsible_type_id blank means "not enabled for this project type" -
  # translate that into a destroy instead of trying to save an invalid link.
  def responsible_project_types_attributes=(attributes)
    attributes = attributes.values if attributes.is_a?(Hash)
    attributes.each { |attrs| attrs[:_destroy] = "1" if attrs[:responsible_type_id].blank? }
    super(attributes)
  end

  private

  def resync_project_responsibles_snapshot
    project_responsibles.update_all(responsible_name: name, responsible_color: color)
  end
end
