class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update]
  before_action :require_admin_or_gerente!, only: [:new, :create, :bulk_assign_installer]
  before_action :authorize_view!, only: [:show]
  before_action :authorize_edit!, only: [:edit]
  before_action :authorize_update!, only: [:update]

  def index
    @statuses = Project.distinct.pluck(:status).compact
    @installers = Installer.all
    @sections = ProjectType.all.map { |project_type| build_section(project_type) }
  end

  def tracker
    @project_types = ProjectType.all
    @installers = Installer.all
    @project_type = ProjectType.find_by(id: params[:project_type_id]) || ProjectType.first
    @projects = if @project_type
      scope = Project.visible_to(current_user).where(project_type: @project_type).where.not(status: "archived")
                     .includes(project_stages: :stage_template).order(:name)
      params[:installer_id].present? ? filter_by_installer(scope, params[:installer_id]) : scope
    else
      Project.none
    end
  end

  def show
    @project_change_versions = PaperTrail::Version
      .where(item_type: "Project", item_id: @project.id)
      .or(PaperTrail::Version.where(item_type: "ProjectStage", item_id: @project.project_stage_ids))
      .order(created_at: :desc)
      .limit(50)

    whodunnit_ids = @project_change_versions.map(&:whodunnit).compact
    @version_authors = User.where(id: whodunnit_ids).index_by { |u| u.id.to_s }
  end

  def new
    @project_type = ProjectType.find(params[:project_type_id]) if params[:project_type_id]
    @project = Project.new(project_type: @project_type)
  end

  def create
    @project = Project.new(project_params)
    @project_type = @project.project_type
    if @project.save
      ProjectAccess.create!(user: current_user, project: @project, can_edit: true) if current_user.gerente?
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
    success =
      if current_user.can_edit_project?(@project)
        @project.update(project_params)
      else
        update_progress_only!
      end

    respond_to do |format|
      format.html do
        if success
          redirect_to project_path(@project)
        else
          render :edit, status: :unprocessable_entity
        end
      end
      format.json do
        if success
          render json: stage_payload
        else
          render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end

  def bulk_assign_installer
    project_ids = Array(params[:project_ids]).reject(&:blank?)
    if params[:installer_id].blank? || project_ids.empty?
      redirect_to projects_path(request.query_parameters), alert: "Elegí un instalador y al menos un proyecto." and return
    end

    editable_projects = Project.visible_to(current_user).where(id: project_ids).select { |project| current_user.can_edit_project?(project) }
    count = 0
    editable_projects.each do |project|
      key = project.project_type.field_definitions.find_by(reference_table: "installers")&.key
      next unless key

      project.custom_fields = project.custom_fields.merge(key => params[:installer_id])
      count += 1 if project.save
    end

    redirect_to projects_path(request.query_parameters), notice: "Instalador asignado a #{count} proyecto(s)."
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def authorize_view!
    return if current_user.can_view_project?(@project)
    redirect_to projects_path, alert: "No tenés acceso a ese proyecto."
  end

  def authorize_edit!
    return if current_user.can_edit_project?(@project)
    redirect_to projects_path, alert: "No tenés permiso para editar ese proyecto."
  end

  def authorize_update!
    return if current_user.can_edit_project?(@project) || current_user.editable_project_stage_ids(@project).any?
    redirect_to projects_path, alert: "No tenés permiso para editar ese proyecto."
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

  def update_progress_only!
    editable_ids = current_user.editable_project_stage_ids(@project).map(&:to_s)
    submitted = params.fetch(:project, {})[:project_stages_attributes] || {}
    submitted.each_value do |attrs|
      next unless editable_ids.include?(attrs["id"].to_s)
      next if attrs["progress_percent"].blank?
      @project.project_stages.find(attrs["id"]).update(progress_percent: attrs["progress_percent"])
    end
    true
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

  def filter_by_date_range(scope, from_date, to_date)
    return scope if from_date.blank? && to_date.blank?

    dated_scope = scope.joins(:project_stages).distinct
    dated_scope = dated_scope.where("project_stages.end_date >= ?", from_date) if from_date.present?
    dated_scope = dated_scope.where("project_stages.start_date <= ?", to_date) if to_date.present?

    dated_stage_project_ids = ProjectStage.where.not(start_date: nil).where.not(end_date: nil).select(:project_id)
    undated_scope = scope.where.not(id: dated_stage_project_ids)

    scope.where(id: dated_scope.reorder(nil).select(:id)).or(scope.where(id: undated_scope.reorder(nil).select(:id)))
  end

  def filter_by_query(scope, q)
    return scope if q.blank?
    term = "%#{q}%"
    scope.where("projects.name ILIKE :term OR projects.custom_fields::text ILIKE :term", term: term)
  end

  def build_section(project_type)
    section_submitted = params.dig(:sections, project_type.slug)
    section_params = section_submitted || {}

    projects = Project.visible_to(current_user).where(project_type: project_type).includes(:project_type, project_stages: :stage_template).order(:name)
    projects = section_params[:status].present? ? projects.where(status: section_params[:status]) : projects.where.not(status: "archived")
    if section_params[:installer_id] == "none"
      projects = filter_by_no_installer(projects)
    elsif section_params[:installer_id].present?
      projects = filter_by_installer(projects, section_params[:installer_id])
    end
    projects = filter_by_date_range(projects, section_params[:from_date], section_params[:to_date])
    projects = filter_by_query(projects, section_params[:q])

    projects_list = projects.to_a
    per_page = 20
    page = [section_params[:page].to_i, 1].max
    total_pages = (projects_list.size / per_page.to_f).ceil
    page_projects = projects_list.drop((page - 1) * per_page).first(per_page)
    stage_names = StageTemplate.where(project_type: project_type).order(:name).pluck(:name)

    stage_name = if section_submitted.nil?
      project_type.stage_templates.find_by(default_in_filter: true)&.name
    else
      section_params[:stage_name]
    end

    {
      project_type: project_type,
      params: section_params,
      stage_name: stage_name,
      projects_list: projects_list,
      page_projects: page_projects,
      page: page,
      total_pages: total_pages,
      stage_names: stage_names
    }
  end
end
