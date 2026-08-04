import { Controller } from "@hotwired/stimulus"

function toDateInputValue(date) {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, "0")
  const day = String(date.getDate()).padStart(2, "0")
  return `${year}-${month}-${day}`
}

// Editable Gantt chart for a single project's stages - dragging a bar's dates
// or progress PATCHes the change back to the server.
export default class extends Controller {
  static targets = ["chart", "viewModeButton"]
  static values = { patchUrl: String, tasks: Array, colors: Array }

  connect() {
    if (this.tasksValue.length === 0) return

    this.gantt = new Gantt(this.chartTarget, this.tasksValue, {
      language: "es",
      popup: false,
      today_button: false,
      container_height: 630,
      view_mode_select: false,
      on_click: (task) => { window.location.hash = `stage-${task.id}` },
      on_date_change: (task, start, end) => {
        this.saveStage(task.id, { start_date: toDateInputValue(start), end_date: toDateInputValue(end) })
      },
      on_progress_change: (task, progress) => {
        this.saveStage(task.id, { progress_percent: Math.round(progress) })
      }
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
      this.chartTarget.querySelectorAll(`.bar-wrapper.stage-color-${id}`).forEach((el) => {
        el.style.setProperty("--bar-fill", color)
      })
    })
  }

  saveStage(stageId, attrs) {
    fetch(this.patchUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({
        project: { project_stages_attributes: { "0": Object.assign({ id: stageId }, attrs) } }
      })
    })
      .then((response) => {
        if (!response.ok) throw new Error("save failed")
        return response.json()
      })
      .then((stages) => {
        const updated = stages.find((s) => String(s.id) === String(stageId))
        if (!updated) return
        const row = document.getElementById(`stage-${stageId}`)
        row.querySelector("input[name*='[start_date]']").value = updated.start_date || ""
        row.querySelector("input[name*='[end_date]']").value = updated.end_date || ""
        row.querySelector("input[name*='[progress_percent]']").value = updated.progress_percent
      })
      .catch(() => {
        this.gantt.refresh(this.tasksValue)
        this.applyColors()
        alert("No se pudo guardar el cambio. Intenta de nuevo.")
      })
  }
}
