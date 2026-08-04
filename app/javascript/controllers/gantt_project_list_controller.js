import { Controller } from "@hotwired/stimulus"

function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]))
}

// Read-only Gantt chart for a list of projects (one project per bar) - clicking
// a bar navigates to the project, hovering shows a popup with its responsibles.
export default class extends Controller {
  static targets = ["chart", "viewModeButton"]
  static values = { tasks: Array, colors: Array }

  connect() {
    if (this.tasksValue.length === 0) return

    this.gantt = new Gantt(this.chartTarget, this.tasksValue, {
      language: "es",
      readonly_dates: true,
      readonly_progress: true,
      today_button: false,
      container_height: 630,
      view_mode_select: false,
      popup_on: "hover",
      on_click: (task) => { window.location = task.edit_url },
      popup: (ctx) => this.buildPopup(ctx.task)
    })
    this.applyColors()
  }

  changeViewMode(event) {
    this.gantt.change_view_mode(event.currentTarget.dataset.mode)
    this.viewModeButtonTargets.forEach((btn) => btn.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this.applyColors()
  }

  applyColors() {
    this.colorsValue.forEach(([id, _name, color]) => {
      this.chartTarget.querySelectorAll(`.bar-wrapper.responsible-color-${id}`).forEach((el) => {
        el.style.setProperty("--bar-fill", color)
      })
    })
  }

  buildPopup(task) {
    const rows = [
      `<span class="badge ${task.status_badge_class}">${escapeHtml(task.status_label)}</span>`,
      `<span class="badge ${task.progress_status_badge_class}">${escapeHtml(task.progress_status_label)}</span>`
    ]
    if (task.overdue) rows.push('<span class="badge bg-danger">Vencido</span>')
    const responsiblesHtml = (task.responsibles || []).map((r) =>
      `<div class="small mt-1"><span class="badge me-1" style="background-color: ${r.color}">&nbsp;</span>${escapeHtml(r.type)}: ${escapeHtml(r.name)}</div>`
    ).join("")
    return `<div class="p-2">
      <div class="fw-bold mb-1">${escapeHtml(task.name)}</div>
      <div class="d-flex gap-1 flex-wrap">${rows.join("")}</div>
      ${responsiblesHtml}
      <div class="small text-white-50 mt-1">${escapeHtml(task.date_range_label)}</div>
    </div>`
  }
}
