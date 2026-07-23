class ProjectType < ApplicationRecord
  has_many :field_definitions, -> { order(:position) }, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
end
