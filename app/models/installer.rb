class Installer < ApplicationRecord
  validates :name, presence: true
end
