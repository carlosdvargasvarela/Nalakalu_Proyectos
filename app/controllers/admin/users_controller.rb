class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [:edit, :update, :destroy]

  def index
    @users = User.all
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to admin_users_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @projects = Project.all.includes(:project_type)
    @project_types = ProjectType.all
  end

  def update
    attrs = user_params
    attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
    if @user.update(attrs)
      sync_access_grants!
      redirect_to admin_users_path
    else
      @projects = Project.all.includes(:project_type)
      @project_types = ProjectType.all
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy
    redirect_to admin_users_path
  rescue ActiveRecord::InvalidForeignKey
    redirect_to admin_users_path, alert: "No se puede eliminar: tiene notas de bitácora o etapas asignadas."
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email, :role, :password, :password_confirmation)
  end

  # ponytail: replaces all of the user's accesses on every save — O(proyectos totales +
  # tipos totales), fine at this pilot's scale. If it grows large, upgrade to diffing
  # (only create/destroy what changed) instead of destroy_all + recreate.
  #
  # Only runs when the request actually came from the access-grants form (marked by
  # `sync_project_access`). The email/role/password form is separate and never submits
  # `project_access`/`project_type_access` at all — without this guard, saving that form
  # would see absent params and wipe every existing grant.
  def sync_access_grants!
    return unless params[:sync_project_access] == "1"

    submitted_projects = params.fetch(:project_access, {})
    @user.project_accesses.destroy_all
    submitted_projects.each do |project_id, flags|
      next unless flags["view"] == "1"
      @user.project_accesses.create!(project_id: project_id, can_edit: flags["edit"] == "1")
    end

    submitted_types = params.fetch(:project_type_access, {})
    @user.project_type_accesses.destroy_all
    submitted_types.each do |project_type_id, flags|
      next unless flags["edit"] == "1"
      @user.project_type_accesses.create!(project_type_id: project_type_id, can_edit: true)
    end
  end
end
