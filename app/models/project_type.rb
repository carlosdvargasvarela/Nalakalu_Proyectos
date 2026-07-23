class ProjectType < ApplicationRecord
  has_many :field_definitions, -> { order(:position) }, dependent: :destroy
  has_many :stage_templates, -> { order(:position) }, dependent: :destroy
  has_many :projects, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
end
