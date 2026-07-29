class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :rememberable, :validatable

  enum :role, { admin: "admin", gerente: "gerente", visor: "visor" }, default: "visor"

  has_many :project_accesses, dependent: :destroy
  has_many :project_type_accesses, dependent: :destroy
  has_many :accessible_projects, through: :project_accesses, source: :project

  def can_view_project?(project)
    return true if admin? || gerente?
    project_accesses.exists?(project_id: project.id)
  end

  def can_edit_project?(project)
    return true if admin?
    return false if visor?
    project_accesses.exists?(project_id: project.id, can_edit: true) ||
      project_type_accesses.exists?(project_type_id: project.project_type_id, can_edit: true)
  end
end
