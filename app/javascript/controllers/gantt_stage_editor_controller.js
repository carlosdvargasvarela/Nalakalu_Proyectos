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
  static targets = ["chart", "viewModeButton", "sortButton"]
  static values = { patchUrl: String, tasks: Array, colors: Array, events: Array }

  connect() {
    if (this.tasksValue.length === 0) return

    this.ascending = true
    this.gantt = new Gantt(this.chartTarget, this.currentOrder(), {
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

  disconnect() {
    this.closeEventPicker()
  }

  changeViewMode(event) {
    this.gantt.change_view_mode(event.currentTarget.dataset.mode)
    this.viewModeButtonTargets.forEach((btn) => btn.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this.refreshVisuals()
  }

  toggleSort() {
    this.ascending = !this.ascending
    this.gantt.refresh(this.currentOrder())
    this.refreshVisuals()
    if (this.hasSortButtonTarget) {
      this.sortButtonTarget.querySelector("i").className = this.ascending ? "bi bi-sort-down" : "bi bi-sort-up"
    }
  }

  currentOrder() {
    return this.ascending ? this.tasksValue : [...this.tasksValue].reverse()
  }

  refreshVisuals() {
    this.applyColors()
    this.drawEventMarkers()
  }

  revertProjectEventsRow() {
    this.gantt.refresh(this.currentOrder())
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
  // Events whose computed X position lands within CLUSTER_THRESHOLD_PX of a
  // neighbor on the same row are merged into one gray "N" marker instead of
  // drawing overlapping diamonds - clicking it opens a small picker listing
  // every grouped event.
  drawEventMarkers() {
    this.chartTarget.querySelectorAll(".event-marker, .event-marker-group").forEach((el) => el.remove())
    this.closeEventPicker()
    const svg = this.chartTarget.querySelector("svg.gantt")
    if (!svg) return

    const CLUSTER_THRESHOLD_PX = 16
    const byStage = {}

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

      const key = evt.project_stage_id
      byStage[key] = byStage[key] || []
      byStage[key].push(Object.assign({}, evt, { cx, cy }))
    })

    Object.values(byStage).forEach((stageEvents) => {
      stageEvents.sort((a, b) => a.cx - b.cx)
      const clusters = []
      stageEvents.forEach((evt) => {
        const last = clusters[clusters.length - 1]
        const lastEvent = last && last[last.length - 1]
        if (lastEvent && evt.cx - lastEvent.cx < CLUSTER_THRESHOLD_PX) {
          last.push(evt)
        } else {
          clusters.push([evt])
        }
      })

      clusters.forEach((cluster) => {
        const avgCx = cluster.reduce((sum, e) => sum + e.cx, 0) / cluster.length
        const cy = cluster[0].cy
        if (cluster.length === 1) {
          this.drawSingleMarker(svg, cluster[0], avgCx, cy)
        } else {
          this.drawClusterMarker(svg, cluster, avgCx, cy)
        }
      })
    })
  }

  drawSingleMarker(svg, evt, cx, cy) {
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
      this.openEventModal(evt.id)
    })

    svg.appendChild(marker)
  }

  drawClusterMarker(svg, events, cx, cy) {
    const size = 10
    const group = document.createElementNS("http://www.w3.org/2000/svg", "g")
    group.setAttribute("class", "event-marker-group")
    group.style.cursor = "pointer"

    const marker = document.createElementNS("http://www.w3.org/2000/svg", "path")
    marker.setAttribute("d", `M ${cx} ${cy - size} L ${cx + size} ${cy} L ${cx} ${cy + size} L ${cx - size} ${cy} Z`)
    marker.setAttribute("fill", "#495057")
    marker.setAttribute("stroke", "#fff")
    marker.setAttribute("stroke-width", "1.5")
    marker.setAttribute("class", "event-marker")
    group.appendChild(marker)

    const label = document.createElementNS("http://www.w3.org/2000/svg", "text")
    label.setAttribute("x", cx)
    label.setAttribute("y", cy)
    label.setAttribute("text-anchor", "middle")
    label.setAttribute("dominant-baseline", "central")
    label.setAttribute("fill", "#fff")
    label.setAttribute("font-size", "10")
    label.textContent = events.length
    group.appendChild(label)

    const title = document.createElementNS("http://www.w3.org/2000/svg", "title")
    title.textContent = events.map((e) => `${e.title} — ${e.event_date}`).join("\n")
    group.appendChild(title)

    group.addEventListener("click", (e) => {
      e.stopPropagation()
      this.openEventPicker(events, cx, cy, svg)
    })

    svg.appendChild(group)
  }

  openEventModal(id) {
    const modalEl = document.getElementById(`edit-event-modal-${id}`)
    if (modalEl) bootstrap.Modal.getOrCreateInstance(modalEl).show()
  }

  openEventPicker(events, cx, cy, svg) {
    this.closeEventPicker()
    const rect = svg.getBoundingClientRect()
    const picker = document.createElement("div")
    picker.setAttribute("role", "menu")
    picker.className = "list-group position-absolute shadow"
    picker.style.zIndex = "1000"
    picker.style.left = `${rect.left + cx + window.scrollX}px`
    picker.style.top = `${rect.top + cy + window.scrollY}px`

    events.forEach((evt) => {
      const item = document.createElement("button")
      item.type = "button"
      item.className = "list-group-item list-group-item-action small"
      item.textContent = `${evt.title} — ${evt.event_date}`
      item.addEventListener("click", () => {
        this.closeEventPicker()
        this.openEventModal(evt.id)
      })
      picker.appendChild(item)
    })

    document.body.appendChild(picker)
    picker.querySelector("button")?.focus()
    this.eventPicker = picker
    this.eventPickerOutsideHandler = (e) => {
      if (!picker.contains(e.target)) this.closeEventPicker()
    }
    this.eventPickerEscapeHandler = (e) => {
      if (e.key === "Escape") this.closeEventPicker()
    }
    setTimeout(() => document.addEventListener("click", this.eventPickerOutsideHandler), 0)
    document.addEventListener("keydown", this.eventPickerEscapeHandler)
  }

  closeEventPicker() {
    if (this.eventPicker) {
      this.eventPicker.remove()
      this.eventPicker = null
    }
    if (this.eventPickerOutsideHandler) {
      document.removeEventListener("click", this.eventPickerOutsideHandler)
      this.eventPickerOutsideHandler = null
    }
    if (this.eventPickerEscapeHandler) {
      document.removeEventListener("keydown", this.eventPickerEscapeHandler)
      this.eventPickerEscapeHandler = null
    }
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
        this.gantt.refresh(this.currentOrder())
        this.refreshVisuals()
        alert("No se pudo guardar el cambio. Intenta de nuevo.")
      })
  }
}
