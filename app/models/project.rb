class Project < ApplicationRecord
  belongs_to :project_type

  validates :name, presence: true
  validate :custom_fields_match_definitions

  private

  def custom_fields_match_definitions
    project_type.field_definitions.each do |field|
      value = custom_fields[field.key]
      next if value.nil?

      case field.data_type
      when "text"
        errors.add(:custom_fields, "#{field.label} debe ser texto") unless value.is_a?(String)
      when "date"
        errors.add(:custom_fields, "#{field.label} debe ser una fecha válida") unless valid_date?(value)
      when "percent"
        errors.add(:custom_fields, "#{field.label} debe ser un porcentaje entre 0 y 100") unless valid_percent?(value)
      when "reference"
        errors.add(:custom_fields, "#{field.label} debe referenciar un registro existente") unless valid_reference?(field, value)
      end
    end
  end

  def valid_date?(value)
    Date.parse(value.to_s)
    true
  rescue ArgumentError, TypeError
    false
  end

  def valid_percent?(value)
    Float(value) rescue false
    Float(value).between?(0, 100)
  rescue ArgumentError, TypeError
    false
  end

  def valid_reference?(field, value)
    field.reference_table.classify.constantize.exists?(id: value)
  rescue NameError
    false
  end
end
