class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :rememberable, :validatable, :recoverable, :confirmable, :registerable

  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end

  enum :role, { admin: "admin", gerente: "gerente", visor: "visor", responsable: "responsable" }, default: "visor"

  has_many :project_accesses, dependent: :destroy
  has_many :project_type_accesses, dependent: :destroy
  has_many :accessible_projects, through: :project_accesses, source: :project
  has_one :responsible, dependent: :nullify

  def can_view_project?(project)
    return true if admin? || gerente?
    return true if visor? && project_accesses.exists?(project_id: project.id)
    return false if responsible.nil?
    ProjectResponsible.where(project_id: project.id, responsible_id: responsible.id).exists?
  end

  def can_edit_project?(project)
    return true if admin?
    return false if visor?
    project_accesses.exists?(project_id: project.id, can_edit: true) ||
      project_type_accesses.exists?(project_type_id: project.project_type_id, can_edit: true)
  end

  def editable_project_stage_ids(project)
    return project.project_stage_ids if admin? || can_edit_project?(project)
    return [] if responsible.nil?

    assignments = ProjectResponsible.where(project_id: project.id, responsible_id: responsible.id)
    return project.project_stage_ids if assignments.any?(&:project_wide?)
    assignments.filter_map(&:project_stage_id)
  end

  def can_create_associated_project?(association, target_project)
    return true if admin? || gerente?
    association.responsables_can_create? && responsable? && can_view_project?(target_project)
  end
end
