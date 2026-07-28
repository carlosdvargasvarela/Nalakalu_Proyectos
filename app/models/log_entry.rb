class LogEntry < ApplicationRecord
  belongs_to :project
  belongs_to :user
  belongs_to :log_entry_type

  has_rich_text :body

  validates :body, presence: true
end
