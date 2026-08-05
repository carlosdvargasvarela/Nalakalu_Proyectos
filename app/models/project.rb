class Project < ApplicationRecord
  has_paper_trail
  belongs_to :project_type
  has_many :project_stages, dependent: :destroy
  has_many :log_entries, dependent: :destroy
  has_many :project_accesses, dependent: :destroy
  has_many :project_responsibles, dependent: :destroy
  has_many :outgoing_project_associations, class_name: "ProjectAssociation", foreign_key: :from_project_id, dependent: :destroy
  has_many :incoming_project_associations, class_name: "ProjectAssociation", foreign_key: :to_project_id, dependent: :destroy
  accepts_nested_attributes_for :project_stages, update_only: true

  validates :name, presence: true
  validate :custom_fields_match_definitions
  after_create :build_stages_from_template

  def self.visible_to(user)
    return all if user.admin? || user.gerente?
    if user.visor?
      accessible = where(id: ProjectAccess.where(user_id: user.id).select(:project_id))
      return accessible if user.responsible.nil?
      return accessible.or(where(id: ProjectResponsible.where(responsible_id: user.responsible.id).select(:project_id)))
    end
    return none if user.responsible.nil?
    joins(:project_responsibles).where(project_responsibles: { responsible_id: user.responsible.id }).distinct
  end

  def start_date
    project_stages.map(&:start_date).compact.min
  end

  def end_date
    project_stages.map(&:end_date).compact.max
  end

  def stages_missing_dates
    project_stages.select { |stage| stage.start_date.blank? || stage.end_date.blank? }
  end

  def gantt_window
    first = start_date || created_at.to_date
    last = end_date || (first + 7.days)
    [first, last]
  end

  def current_stage
    project_stages.select { |stage| stage.progress_percent > 0 }.max_by(&:id) || project_stages.min_by(&:id)
  end

  def responsible_for(responsible_type)
    project_responsibles.find { |pr| pr.responsible_type_id == responsible_type.id && pr.project_wide? }&.responsible
  end

  def progress_status
    return "sin_iniciar" if project_stages.all? { |stage| stage.progress_percent.zero? }
    return "finalizado" if project_stages.all? { |stage| stage.progress_percent == 100 }
    "iniciado"
  end

  def overdue?
    end_date.present? && end_date < Date.current && progress_status != "finalizado"
  end

  private

  def build_stages_from_template
    project_type.stage_templates.each do |template|
      project_stages.create!(stage_template: template, name: template.name)
    end
  end

  def custom_fields_match_definitions
    project_type.field_definitions.each do |field|
      value = custom_fields[field.key]
      next if value.nil? || value == ""

      case field.data_type
      when "text", "textarea"
        errors.add(:custom_fields, "#{field.label} debe ser texto") unless value.is_a?(String)
      when "date"
        errors.add(:custom_fields, "#{field.label} debe ser una fecha válida") unless valid_date?(value)
      when "percent"
        errors.add(:custom_fields, "#{field.label} debe ser un porcentaje entre 0 y 100") unless valid_percent?(value)
      when "number", "currency"
        errors.add(:custom_fields, "#{field.label} debe ser un número") unless valid_number?(value)
      when "boolean"
        errors.add(:custom_fields, "#{field.label} debe ser Sí o No") unless valid_boolean?(value)
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
    Float(value).between?(0, 100)
  rescue ArgumentError, TypeError
    false
  end

  def valid_number?(value)
    Float(value)
    true
  rescue ArgumentError, TypeError
    false
  end

  def valid_boolean?(value)
    %w[true false].include?(value.to_s.downcase)
  end

  def valid_reference?(field, value)
    field.reference_table.classify.constantize.exists?(id: value)
  rescue NameError, NoMethodError
    false
  end
end
