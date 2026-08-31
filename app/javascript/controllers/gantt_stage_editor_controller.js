import { Controller } from "@hotwired/stimulus"
import { applyBarColors } from "gantt_bar_colors"

function toDateInputValue(date) {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, "0")
  const day = String(date.getDate()).padStart(2, "0")
  return `${year}-${month}-${day}`
}

function isProjectEventsRow(id) {
  return id === "project-events"
}

// Editable Gantt chart for a single project's stages - dragging a bar's dates
// or progress PATCHes the change back to the server. Also overlays a colored
// diamond marker on a stage's bar for each event tied to that stage. Events
// with no stage are grouped onto a single synthetic "project-events" row
// (already present in tasksValue - see projects/show.html.erb) since
// frappe-gantt 1.2.2 ignores `type: "milestone"`.
export default class extends Controller {
  static targets = ["chart", "viewModeButton"]
  static values = { patchUrl: String, tasks: Array, colors: Array, events: Array }

  connect() {
    if (this.tasksValue.length === 0) return

    this.gantt = new Gantt(this.chartTarget, this.tasksValue, {
      language: "es",
      popup: false,
      today_button: false,
      container_height: 630,
      view_mode_select: false,
      // frappe-gantt defaults infinite_padding to true, which wipes and
      // redraws every bar (this.clear() + this.render()) when the user
      // scrolls near an edge - that loses the --bar-fill custom property
      // applyColors() set on the old nodes. We don't need scroll-driven
      // date-range extension (tasksValue is already the full, fixed set).
      infinite_padding: false,
      on_click: (task) => {
        if (isProjectEventsRow(task.id)) return
        window.location.hash = `stage-${task.id}`
      },
      on_date_change: (task, start, end) => {
        if (isProjectEventsRow(task.id)) return this.revertProjectEventsRow()
        this.saveStage(task.id, { start_date: toDateInputValue(start), end_date: toDateInputValue(end) })
      },
      on_progress_change: (task, progress) => {
        if (isProjectEventsRow(task.id)) return this.revertProjectEventsRow()
        this.saveStage(task.id, { progress_percent: Math.round(progress) })
      }
    })
    this.refreshVisuals()
  }

  changeViewMode(event) {
    this.gantt.change_view_mode(event.currentTarget.dataset.mode)
    this.viewModeButtonTargets.forEach((btn) => btn.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this.refreshVisuals()
  }

  refreshVisuals() {
    this.applyColors()
    this.drawEventMarkers()
  }

  revertProjectEventsRow() {
    this.gantt.refresh(this.tasksValue)
    this.refreshVisuals()
  }

  applyColors() {
    applyBarColors(this.chartTarget, this.colorsValue, "stage-color")
  }

  // Overlays a small diamond on a stage's bar for each event scoped to that
  // stage. Position is derived from the stage bar's own rendered SVG geometry
  // (x/width/y/height already reflect the current view mode's column width),
  // not from frappe-gantt's internal date_utils/config - which keeps this
  // independent of the vendored library's private implementation details.
  drawEventMarkers() {
    this.chartTarget.querySelectorAll(".event-marker").forEach((el) => el.remove())
    const svg = this.chartTarget.querySelector("svg.gantt")
    if (!svg) return

    this.eventsValue.forEach((evt) => {
      const barWrapper = this.chartTarget.querySelector(`.bar-wrapper[data-id="${evt.project_stage_id}"]`)
      const stageTask = this.tasksValue.find((t) => String(t.id) === String(evt.project_stage_id))
      if (!barWrapper || !stageTask) return
      const bar = barWrapper.querySelector(".bar")
      if (!bar) return

      const barX = parseFloat(bar.getAttribute("x"))
      const barWidth = parseFloat(bar.getAttribute("width"))
      const barY = parseFloat(bar.getAttribute("y"))
      const barHeight = parseFloat(bar.getAttribute("height"))
      const stageStart = new Date(stageTask.start)
      const stageEnd = new Date(stageTask.end)
      const eventDate = new Date(evt.event_date)
      const span = stageEnd - stageStart
      const fraction = span > 0 ? Math.min(Math.max((eventDate - stageStart) / span, 0), 1) : 0

      const cx = barX + barWidth * fraction
      const cy = barY + barHeight / 2
      const size = 7

      const marker = document.createElementNS("http://www.w3.org/2000/svg", "path")
      marker.setAttribute("d", `M ${cx} ${cy - size} L ${cx + size} ${cy} L ${cx} ${cy + size} L ${cx - size} ${cy} Z`)
      marker.setAttribute("fill", evt.color)
      marker.setAttribute("stroke", "#fff")
      marker.setAttribute("stroke-width", "1.5")
      marker.setAttribute("class", "event-marker")
      marker.style.cursor = "pointer"

      const title = document.createElementNS("http://www.w3.org/2000/svg", "title")
      title.textContent = `${evt.title} — ${evt.event_date}`
      marker.appendChild(title)

      marker.addEventListener("click", (e) => {
        e.stopPropagation()
        const modalEl = document.getElementById(`edit-event-modal-${evt.id}`)
        if (modalEl) bootstrap.Modal.getOrCreateInstance(modalEl).show()
      })

      svg.appendChild(marker)
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
        this.drawEventMarkers()
      })
      .catch(() => {
        this.gantt.refresh(this.tasksValue)
        this.refreshVisuals()
        alert("No se pudo guardar el cambio. Intenta de nuevo.")
      })
  }
}
