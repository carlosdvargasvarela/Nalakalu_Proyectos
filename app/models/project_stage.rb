class ProjectStage < ApplicationRecord
  belongs_to :project
  belongs_to :stage_template, optional: true
  belongs_to :user, optional: true

  validates :name, presence: true
  validates :progress_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  def progress_status
    return "finalizado" if progress_percent == 100
    return "sin_iniciar" if progress_percent.zero?
    "iniciado"
  end

  def overdue?
    end_date.present? && end_date < Date.current && progress_percent < 100
  end
end
