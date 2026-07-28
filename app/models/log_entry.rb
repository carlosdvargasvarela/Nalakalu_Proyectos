class LogEntry < ApplicationRecord
  belongs_to :project
  belongs_to :user
  belongs_to :log_entry_type

  validates :body, presence: true
end
