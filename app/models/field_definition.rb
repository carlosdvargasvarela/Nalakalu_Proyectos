class FieldDefinition < ApplicationRecord
  DATA_TYPES = %w[text date percent reference].freeze

  belongs_to :project_type

  validates :key, presence: true, uniqueness: { scope: :project_type_id }
  validates :label, presence: true
  validates :data_type, inclusion: { in: DATA_TYPES }
  validates :reference_table, presence: true, if: -> { data_type == "reference" }
end
