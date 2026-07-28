class LogEntryType < ApplicationRecord
  belongs_to :project_type
  # has_many :log_entries, dependent: :restrict_with_error — deferred to Task 3,
  # which creates the LogEntry model this association depends on.

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9a-fA-F]{6}\z/, message: "debe ser un color hexadecimal (ej. #6c757d)" }
end
