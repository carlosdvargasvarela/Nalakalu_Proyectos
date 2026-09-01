class ProjectStage < ApplicationRecord
  has_paper_trail
  belongs_to :project
  belongs_to :stage_template, optional: true
  belongs_to :user, optional: true
  has_many :project_responsibles, dependent: :destroy
  has_many :events, dependent: :nullify

  scope :applicable, -> { where(not_applicable: false) }

  validates :name, presence: true
  validates :progress_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }

  def progress_status
    return "finalizado" if progress_percent == 100
    return "sin_iniciar" if progress_percent.zero?
    "iniciado"
  end

  def overdue?
    end_date.present? && end_date < Date.current && progress_percent < 100
  end

  def dates_missing?
    start_date.blank? || end_date.blank?
  end
end
