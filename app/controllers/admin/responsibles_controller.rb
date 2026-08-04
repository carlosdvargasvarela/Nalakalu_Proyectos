class Admin::ResponsiblesController < Admin::BaseController
  before_action :set_responsible, only: [:edit, :update, :destroy]

  def index
    @responsibles = Responsible.all
  end

  def new
    @responsible = Responsible.new
    build_responsible_project_type_rows
  end

  def create
    @responsible = Responsible.new(responsible_params)
    if @responsible.save
      redirect_to admin_responsibles_path
    else
      build_responsible_project_type_rows
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    build_responsible_project_type_rows
  end

  def update
    if @responsible.update(responsible_params)
      redirect_to admin_responsibles_path
    else
      build_responsible_project_type_rows
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @responsible.destroy
    redirect_to admin_responsibles_path
  end

  private

  def set_responsible
    @responsible = Responsible.find(params[:id])
  end

  def unlinked_users
    User.where.missing(:responsible).or(User.where(id: @responsible&.user_id))
  end
  helper_method :unlinked_users

  # Ensures every ProjectType has a (possibly unsaved) row to render a select for.
  def build_responsible_project_type_rows
    linked_project_type_ids = @responsible.responsible_project_types.map(&:project_type_id)
    ProjectType.where.not(id: linked_project_type_ids).order(:name).each do |project_type|
      @responsible.responsible_project_types.build(project_type_id: project_type.id)
    end
  end

  def responsible_params
    params.require(:responsible).permit(:name, :color, :user_id,
      responsible_project_types_attributes: [:id, :project_type_id, :responsible_type_id])
  end
end
