module ApplicationHelper
  HELP_MENU = [
    { section: "Proyectos", items: [["Proyectos", "projects"], ["Importar", "imports"]] },
    { section: "Administración", items: [
      ["Tipos de proyecto", "admin/project_types"],
      ["Campos", "admin/field_definitions"],
      ["Subprocesos", "admin/stage_templates"],
      ["Perfiles de duración", "admin/duration_profiles"],
      ["Tipos de bitácora", "admin/log_entry_types"],
      ["Tipos de responsable", "admin/responsible_types"],
      ["Responsables", "admin/responsibles"],
      ["Tipos de asociación", "admin/project_type_associations"],
      ["Usuarios", "admin/users"],
    ] },
  ].freeze

  STATUS_LABELS = { "active" => "Activo", "archived" => "Archivado" }.freeze
  STATUS_BADGE_CLASSES = { "active" => "bg-success", "archived" => "bg-secondary" }.freeze
  PROGRESS_STATUS_LABELS = { "sin_iniciar" => "Sin iniciar", "iniciado" => "Iniciado", "finalizado" => "Finalizado" }.freeze
  PROGRESS_STATUS_BADGE_CLASSES = { "sin_iniciar" => "bg-secondary", "iniciado" => "bg-info text-dark", "finalizado" => "bg-success" }.freeze
  ROLE_LABELS = { "admin" => "Administrador", "gerente" => "Gerente", "visor" => "Visor", "responsable" => "Responsable" }.freeze
  ROLE_BADGE_CLASSES = { "admin" => "bg-primary", "gerente" => "bg-info text-dark", "visor" => "bg-secondary", "responsable" => "bg-warning text-dark" }.freeze

  def status_label(status)
    STATUS_LABELS.fetch(status, status)
  end

  def role_label(role)
    ROLE_LABELS.fetch(role, role)
  end

  def role_badge_class(role)
    ROLE_BADGE_CLASSES.fetch(role, "bg-light text-dark")
  end

  def status_badge(status)
    tag.span(status_label(status), class: "badge #{STATUS_BADGE_CLASSES.fetch(status, 'bg-light text-dark')}")
  end

  def progress_status_label(progress_status)
    PROGRESS_STATUS_LABELS.fetch(progress_status, progress_status)
  end

  def progress_status_badge(progress_status)
    tag.span(progress_status_label(progress_status), class: "badge #{PROGRESS_STATUS_BADGE_CLASSES.fetch(progress_status, 'bg-light text-dark')}")
  end

  def overdue_badge
    tag.span("Vencido", class: "badge bg-danger")
  end

  def pending_stage_dates_count(user)
    Project.visible_to(user)
      .where.not(status: "archived")
      .joins(:project_type, :project_stages)
      .where("project_types.require_stage_dates = TRUE OR project_types.auto_stage_duration_enabled = TRUE")
      .where("project_stages.start_date IS NULL OR project_stages.end_date IS NULL")
      .distinct
      .count
  end

  def format_change_value(value)
    return "(vacío)" if value.blank?
    return l(value, format: :long) if value.respond_to?(:strftime)
    value.to_s
  end

  def help_topic_path_if_exists
    Rails.root.join("docs", "help", "#{controller_path}.md").exist? ? controller_path : nil
  end

  def panel_card(title, &block)
    content_tag(:div, class: "card mb-4") do
      content_tag(:div, title, class: "card-header fw-semibold") +
        content_tag(:div, capture(&block), class: "card-body")
    end
  end
end
