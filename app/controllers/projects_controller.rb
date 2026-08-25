class ProjectsController < ApplicationController
  before_action :set_project, only: [:show, :edit, :update, :apply_auto_duration]
  before_action :require_admin_or_gerente!, only: [:bulk_assign_responsible]
  before_action :authorize_new!, only: [:new, :create]
  before_action :authorize_view!, only: [:show]
  before_action :authorize_edit!, only: [:edit, :apply_auto_duration]
  before_action :authorize_update!, only: [:update]

  def index
    @project_type = ProjectType.find_by(slug: params[:slug]) || ProjectType.first
    return render(:index) if @project_type.nil?
    return redirect_to(project_type_projects_path(@project_type.slug)) if params[:slug].blank? || params[:slug] != @project_type.slug

    @project_types = ProjectType.all
    @statuses = Project.distinct.pluck(:status).compact
    @section = build_section(@project_type)
  end

  def tracker
    @project_types = ProjectType.all
    @project_type = ProjectType.find_by(id: params[:project_type_id]) || ProjectType.first
    @responsible_types = @project_type ? @project_type.responsible_types : ResponsibleType.none
    @responsible_type_id = if params.key?(:responsible_type_id)
      params[:responsible_type_id]
    else
      @project_type&.responsible_types&.find_by(default_in_filter: true)&.id&.to_s
    end
    @projects = if @project_type
      scope = Project.visible_to(current_user).where(project_type: @project_type).where.not(status: "archived")
                     .includes(project_stages: :stage_template, project_responsibles: :responsible_type).order(:name)
      filter_by_responsible(scope, @responsible_type_id, params[:responsible_id])
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
      .includes(:item)

    whodunnit_ids = @project_change_versions.map(&:whodunnit).compact
    @version_authors = User.where(id: whodunnit_ids).index_by { |u| u.id.to_s }
  end

  def new
    @project_type = ProjectType.find(params[:project_type_id]) if params[:project_type_id]
    @project = Project.new(project_type: @project_type)
    @project_type_association_id = params[:project_type_association_id]
    @associate_with_project_id = params[:associate_with_project_id]
    copies = shared_field_copies(@project_type_association_id, @associate_with_project_id)
    @project.custom_fields = copies[:custom_fields]
    @project.name = copies[:name] if copies[:name].present?
  end

  def create
    @project = Project.new(project_params)
    @project.auto_duration_start_date = params[:auto_duration_start_date] if params[:auto_duration_start_date].present?
    @project_type = @project.project_type
    fill_missing_shared_fields
    if @project.save
      ProjectAccess.create!(user: current_user, project: @project, can_edit: true) if current_user.gerente?
      if params[:project_type_association_id].present? && params[:associate_with_project_id].present?
        ProjectAssociation.create!(
          from_project: @project, to_project_id: params[:associate_with_project_id],
          project_type_association_id: params[:project_type_association_id]
        )
        redirect_to project_path(params[:associate_with_project_id])
      else
        redirect_to project_path(@project)
      end
    else
      @project_type_association_id = params[:project_type_association_id]
      @associate_with_project_id = params[:associate_with_project_id]
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

  def apply_auto_duration
    if @project.apply_auto_duration!(params[:start_date])
      redirect_back fallback_location: projects_path, notice: "Fechas calculadas automáticamente."
    else
      redirect_back fallback_location: projects_path, alert: "No se pudo calcular la duración: revisá el valor de referencia y los perfiles configurados."
    end
  end

  def bulk_assign_responsible
    project_ids = Array(params[:project_ids]).reject(&:blank?)
    if params[:responsible_type_id].blank? || params[:responsible_id].blank? || project_ids.empty?
      redirect_to bulk_assign_redirect_target, alert: "Elegí un tipo, un responsable y al menos un proyecto." and return
    end

    responsible = Responsible.find_by(id: params[:responsible_id])
    editable_projects = Project.visible_to(current_user).where(id: project_ids).select { |project| current_user.can_edit_project?(project) }
    eligible, ineligible = editable_projects.partition do |project|
      responsible&.responsible_project_types&.exists?(project_type_id: project.project_type_id, responsible_type_id: params[:responsible_type_id])
    end

    eligible.each do |project|
      project.project_responsibles.find_by(responsible_type_id: params[:responsible_type_id], project_stage_id: nil)&.destroy
      project.project_responsibles.create!(responsible_type_id: params[:responsible_type_id], responsible_id: params[:responsible_id])
    end

    if ineligible.empty?
      redirect_to bulk_assign_redirect_target, notice: "Responsable asignado a #{eligible.size} proyecto(s)."
    else
      redirect_to bulk_assign_redirect_target, alert: "Ese responsable no es del tipo elegido para #{ineligible.size} proyecto(s); se omitieron."
    end
  end

  private

  def bulk_assign_redirect_target
    return projects_path(request.query_parameters) if params[:project_type_slug].blank?
    project_type_projects_path(params[:project_type_slug], request.query_parameters.except("project_type_slug"))
  end

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

  def authorize_new!
    return if current_user.admin? || current_user.gerente?
    association = ProjectTypeAssociation.find_by(id: params[:project_type_association_id])
    target_project = Project.find_by(id: params[:associate_with_project_id])
    return if association && target_project && current_user.can_create_associated_project?(association, target_project)
    redirect_to projects_path, alert: "No tenés permiso para crear proyectos."
  end

  def fill_missing_shared_fields
    copies = shared_field_copies(params[:project_type_association_id], params[:associate_with_project_id])
    copies[:custom_fields].each do |key, value|
      @project.custom_fields[key] = value if @project.custom_fields[key].blank?
    end
    @project.name = copies[:name] if copies[:name].present? && @project.name.blank?
  end

  # The quick-create button lives on a `to_project_type` project (the existing one, `source`)
  # and creates a `from_project_type` project (the new one). A mapping's "from" key belongs to
  # from_project_type (the new project); its "to" key belongs to to_project_type (source's type).
  # The value we're copying already lives on `source`, under the "to" key. "name" is a project
  # attribute, not a custom_fields key, so it's handled separately from the rest.
  def shared_field_copies(association_id, source_id)
    empty = { custom_fields: {}, name: nil }
    return empty if association_id.blank? || source_id.blank?
    association = ProjectTypeAssociation.find_by(id: association_id)
    source = Project.find_by(id: source_id)
    return empty if association.nil? || source.nil?

    from_fields = shareable_field_infos(association.from_project_type)
    to_fields = shareable_field_infos(association.to_project_type)

    association.shared_field_mappings.each_with_object(empty.merge(custom_fields: {})) do |mapping, result|
      from_field = from_fields[mapping["from"]]
      to_field = to_fields[mapping["to"]]
      next unless from_field && to_field
      next unless from_field[:data_type] == to_field[:data_type]
      next if from_field[:data_type] == "reference" && from_field[:reference_table] != to_field[:reference_table]

      value = mapping["to"] == "name" ? source.name : source.custom_fields[mapping["to"]]
      next if value.blank?

      if mapping["from"] == "name"
        result[:name] = value
      else
        result[:custom_fields][mapping["from"]] = value
      end
    end
  end

  def shareable_field_infos(project_type)
    { "name" => { data_type: "text", reference_table: nil } }.merge(
      project_type.field_definitions.index_by(&:key).transform_values { |f| { data_type: f.data_type, reference_table: f.reference_table } }
    )
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

  def filter_by_responsible(scope, responsible_type_id, responsible_id)
    return scope if responsible_type_id.blank?
    matching = ProjectResponsible.where(responsible_type_id: responsible_type_id)
    if responsible_id.blank?
      scope
    elsif responsible_id == "none"
      scope.where.not(id: matching.select(:project_id))
    else
      scope.where(id: matching.where(responsible_id: responsible_id).select(:project_id))
    end
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
    filtered = params.key?(:status)

    responsible_type_id = if filtered
      params[:responsible_type_id]
    else
      params[:responsible_type_id].presence || project_type.responsible_types.find_by(default_in_filter: true)&.id&.to_s
    end

    projects = Project.visible_to(current_user).where(project_type: project_type).includes(:project_type, project_stages: :stage_template, project_responsibles: :responsible_type).order(:name)
    projects = params[:status].present? ? projects.where(status: params[:status]) : projects.where.not(status: "archived")
    projects = filter_by_responsible(projects, responsible_type_id, params[:responsible_id])
    projects = filter_by_date_range(projects, params[:from_date], params[:to_date])
    projects = filter_by_query(projects, params[:q])

    projects_list = projects.to_a
    per_page = 20
    page = [params[:page].to_i, 1].max
    total_pages = (projects_list.size / per_page.to_f).ceil
    page_projects = projects_list.drop((page - 1) * per_page).first(per_page)
    stage_names = StageTemplate.where(project_type: project_type).order(:name).pluck(:name)

    stage_name = if filtered
      params[:stage_name]
    else
      project_type.stage_templates.find_by(default_in_filter: true)&.name
    end

    {
      project_type: project_type,
      params: params.slice(:status, :responsible_type_id, :responsible_id, :from_date, :to_date, :stage_name, :q, :page).merge(responsible_type_id: responsible_type_id),
      stage_name: stage_name,
      projects_list: projects_list,
      page_projects: page_projects,
      page: page,
      total_pages: total_pages,
      stage_names: stage_names
    }
  end
end
