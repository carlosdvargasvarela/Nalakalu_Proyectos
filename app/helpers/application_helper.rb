module ApplicationHelper
  STATUS_LABELS = { "active" => "Activo", "archived" => "Archivado" }.freeze
  STATUS_BADGE_CLASSES = { "active" => "bg-success", "archived" => "bg-secondary" }.freeze
  PROGRESS_STATUS_LABELS = { "sin_iniciar" => "Sin iniciar", "iniciado" => "Iniciado", "finalizado" => "Finalizado" }.freeze
  PROGRESS_STATUS_BADGE_CLASSES = { "sin_iniciar" => "bg-secondary", "iniciado" => "bg-info text-dark", "finalizado" => "bg-success" }.freeze

  def status_label(status)
    STATUS_LABELS.fetch(status, status)
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
end
