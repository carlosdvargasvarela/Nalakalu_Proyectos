class Admin::ProjectTypesController < Admin::BaseController
  before_action :set_project_type, only: [:show, :edit, :update, :destroy]

  def index
    @project_types = ProjectType.all
  end

  def show
  end

  def new
    @project_type = ProjectType.new
  end

  def create
    @project_type = ProjectType.new(project_type_params)
    if @project_type.save
      redirect_to admin_project_type_path(@project_type)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @project_type.update(project_type_params)
      redirect_to admin_project_type_path(@project_type)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project_type.destroy
    redirect_to admin_project_types_path
  end

  private

  def set_project_type
    @project_type = ProjectType.find(params[:id])
  end

  def project_type_params
    params.require(:project_type).permit(:name, :slug, :require_stage_dates, :auto_stage_duration_enabled, :duration_reference_field_definition_id)
  end
end
