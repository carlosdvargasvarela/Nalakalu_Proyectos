class Admin::ResponsibleTypesController < Admin::BaseController
  before_action :set_project_type
  before_action :set_responsible_type, only: [:edit, :update, :destroy]

  def new
    @responsible_type = @project_type.responsible_types.new
  end

  def create
    @responsible_type = @project_type.responsible_types.new(responsible_type_params)
    if @responsible_type.save
      redirect_to admin_project_type_path(@project_type)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @responsible_type.update(responsible_type_params)
      redirect_to admin_project_type_path(@project_type)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @responsible_type.destroy
    redirect_to admin_project_type_path(@project_type)
  end

  private

  def set_project_type
    @project_type = ProjectType.find(params[:project_type_id])
  end

  def set_responsible_type
    @responsible_type = @project_type.responsible_types.find(params[:id])
  end

  def responsible_type_params
    params.require(:responsible_type).permit(:name)
  end
end
