class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update]

  def index
    @projects = Project.includes(:project_type).where.not(status: "archived")
  end

  def dashboard
    @project_types = ProjectType.all
    @statuses = Project.distinct.pluck(:status).compact
    @projects = Project.includes(:project_type, project_stages: :stage_template).all
    @projects = @projects.where(project_type_id: params[:project_type_id]) if params[:project_type_id].present?
    @projects = @projects.where(status: params[:status]) if params[:status].present?
  end

  def show
  end

  def new
    @project_type = ProjectType.find(params[:project_type_id]) if params[:project_type_id]
    @project = Project.new(project_type: @project_type)
  end

  def create
    @project = Project.new(project_params)
    @project_type = @project.project_type
    if @project.save
      redirect_to project_path(@project)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @project_type = @project.project_type
  end

  def update
    @project_type = @project.project_type
    if @project.update(project_params)
      redirect_to project_path(@project)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:project_type_id, :name, :status, custom_fields: {})
  end
end
