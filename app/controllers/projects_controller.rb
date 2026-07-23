class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update]

  def index
    @project_types = ProjectType.all
    @statuses = Project.distinct.pluck(:status).compact
    @installers = Installer.all
    @projects = Project.includes(:project_type, project_stages: :stage_template)
    @projects = params[:status].present? ? @projects.where(status: params[:status]) : @projects.where.not(status: "archived")
    @projects = @projects.where(project_type_id: params[:project_type_id]) if params[:project_type_id].present?
    if params[:installer_id] == "none"
      @projects = filter_by_no_installer(@projects)
    elsif params[:installer_id].present?
      @projects = filter_by_installer(@projects, params[:installer_id])
    end
  end

  def tracker
    @project_types = ProjectType.all
    @installers = Installer.all
    @project_type = ProjectType.find_by(id: params[:project_type_id]) || ProjectType.first
    @projects = if @project_type
      scope = Project.where(project_type: @project_type).where.not(status: "archived")
                     .includes(project_stages: :stage_template).order(:name)
      params[:installer_id].present? ? filter_by_installer(scope, params[:installer_id]) : scope
    else
      Project.none
    end
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
      respond_to do |format|
        format.html { redirect_to project_path(@project) }
        format.json { render json: stage_payload }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def bulk_assign_installer
    redirect_params = request.query_parameters.merge(params.permit(:project_type_id))
    project_ids = Array(params[:project_ids]).reject(&:blank?)
    if params[:installer_id].blank? || project_ids.empty?
      redirect_to projects_path(redirect_params), alert: "Elegí un instalador y al menos un proyecto." and return
    end

    count = 0
    Project.where(id: project_ids).find_each do |project|
      key = project.project_type.field_definitions.find_by(reference_table: "installers")&.key
      next unless key

      project.custom_fields = project.custom_fields.merge(key => params[:installer_id])
      count += 1 if project.save
    end

    redirect_to projects_path(redirect_params), notice: "Instalador asignado a #{count} proyecto(s)."
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(
      :project_type_id, :name, :status, custom_fields: {},
      project_stages_attributes: [:id, :start_date, :end_date, :progress_percent]
    )
  end

  def stage_payload
    @project.project_stages.map do |stage|
      { id: stage.id, start_date: stage.start_date, end_date: stage.end_date, progress_percent: stage.progress_percent }
    end
  end

  def filter_by_installer(scope, installer_id)
    keys = FieldDefinition.where(reference_table: "installers").distinct.pluck(:key)
    return scope.none if keys.empty?
    keys.map { |key| scope.where("custom_fields ->> ? = ?", key, installer_id.to_s) }.reduce(:or)
  end

  def filter_by_no_installer(scope)
    keys = FieldDefinition.where(reference_table: "installers").distinct.pluck(:key)
    return scope if keys.empty?
    keys.reduce(scope) { |s, key| s.where("custom_fields ->> ? IS NULL OR custom_fields ->> ? = ''", key, key) }
  end
end
