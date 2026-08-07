class DurationProfile < ApplicationRecord
  OPERATORS = %w[greater_than less_than between equal_to].freeze

  belongs_to :project_type

  validates :operator, inclusion: { in: OPERATORS }
  validate :values_present_for_operator
  validate :durations_reference_valid_stage_templates

  def matches?(value)
    case operator
    when "greater_than" then min_value.present? && value > min_value
    when "less_than" then max_value.present? && value < max_value
    when "between" then min_value.present? && max_value.present? && value.between?(min_value, max_value)
    when "equal_to" then min_value.present? && value == min_value
    else false
    end
  end

  private

  def values_present_for_operator
    case operator
    when "greater_than", "equal_to"
      errors.add(:min_value, "es obligatorio para este operador") if min_value.blank?
    when "less_than"
      errors.add(:max_value, "es obligatorio para este operador") if max_value.blank?
    when "between"
      errors.add(:min_value, "es obligatorio para este operador") if min_value.blank?
      errors.add(:max_value, "es obligatorio para este operador") if max_value.blank?
      if min_value.present? && max_value.present? && min_value > max_value
        errors.add(:max_value, "debe ser mayor o igual al valor mínimo")
      end
    end
  end

  def durations_reference_valid_stage_templates
    return if durations.blank?
    valid_ids = project_type.stage_templates.pluck(:id).map(&:to_s)
    durations.each do |stage_template_id, days|
      unless valid_ids.include?(stage_template_id.to_s)
        errors.add(:durations, "hace referencia a un subproceso inválido")
        next
      end
      next if days.blank?
      unless days.to_s.match?(/\A\d+\z/) && days.to_i.positive?
        errors.add(:durations, "debe ser un número de días positivo")
      end
    end
  end
end
