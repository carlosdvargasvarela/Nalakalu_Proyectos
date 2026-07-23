class FieldDefinition < ApplicationRecord
  DATA_TYPES = %w[text textarea number currency percent date boolean reference].freeze
  DATA_TYPE_LABELS = {
    "text" => "Texto",
    "textarea" => "Texto largo",
    "number" => "Número",
    "currency" => "Monto (₡)",
    "percent" => "Porcentaje",
    "date" => "Fecha",
    "boolean" => "Sí/No",
    "reference" => "Referencia"
  }.freeze

  belongs_to :project_type

  validates :key, presence: true, uniqueness: { scope: :project_type_id }
  validates :label, presence: true
  validates :data_type, inclusion: { in: DATA_TYPES }
  validates :reference_table, presence: true, if: -> { data_type == "reference" }

  def data_type_label
    DATA_TYPE_LABELS.fetch(data_type, data_type)
  end
end
