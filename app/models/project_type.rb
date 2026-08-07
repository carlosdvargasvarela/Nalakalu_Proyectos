class ProjectType < ApplicationRecord
  has_many :field_definitions, -> { order(:position) }, dependent: :destroy
  has_many :stage_templates, -> { order(:position) }, dependent: :destroy
  has_many :duration_profiles, -> { order(:position) }, dependent: :destroy
  belongs_to :duration_reference_field_definition, class_name: "FieldDefinition", optional: true
  has_many :log_entry_types, dependent: :destroy
  has_many :responsible_types, dependent: :destroy
  has_many :responsible_project_types, dependent: :destroy
  has_many :responsibles, through: :responsible_project_types
  has_many :projects, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true

  after_create :seed_default_log_entry_types

  private

  def seed_default_log_entry_types
    %w[Nota Incidencia Cambio].each { |name| log_entry_types.create!(name: name) }
  end
end
