# Agrupación de marcadores y aviso de fecha fuera de etapa Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Group Gantt event markers that fall within 16px of each other on the same row into a single clustered marker with a picker menu, and warn (without blocking) in the event form when the chosen date falls outside the chosen stage's date range.

**Architecture:** Both changes are client-side only. `drawEventMarkers()` in the existing `gantt_stage_editor_controller.js` gains a clustering pass before drawing; a new small Stimulus controller (`event_date_range_warning_controller.js`) watches the shared `_event_fields.html.erb` partial's stage/date inputs and toggles a warning `<div>`. No model or backend changes.

**Tech Stack:** Stimulus, plain SVG DOM APIs (no new dependency), Capybara/Selenium system tests (existing pattern in `test/system/gantt_event_markers_test.rb`).

**Spec:** `docs/superpowers/specs/2026-08-31-eventos-gantt-agrupacion-warning-design.md`

## Global Constraints

- Cluster threshold is a fixed 16px, independent of Día/Semana/Mes view mode (the bar geometry already reflects the current column width, so a fixed pixel threshold stays correct at any zoom).
- Cluster marker fill is `#495057` (neutral gray) — never one of the grouped events' own colors.
- The date-range warning never blocks form submission and adds no model/controller validation — purely a `hidden` toggle on an existing element.
- No new npm/importmap dependency. Reuse `bootstrap.Modal.getOrCreateInstance` (already used in `gantt_stage_editor_controller.js` and `help_controller.js`) for opening an individual event's edit modal from the picker.

---

### Task 1: Cluster nearby event markers in the Gantt

**Files:**
- Modify: `app/javascript/controllers/gantt_stage_editor_controller.js`
- Modify: `test/system/gantt_event_markers_test.rb`

**Interfaces:**
- Consumes: `this.eventsValue` (existing, unchanged shape: `{id, project_stage_id, event_date, title, color}`), `this.tasksValue` (existing).
- Produces: `.event-marker` (single-event diamond, unchanged from before), `.event-marker-group` (new: a `<g>` containing a gray diamond `.event-marker` + a count `<text>`), both clickable — a single marker opens `#edit-event-modal-<id>` directly (unchanged); a group marker opens a floating picker list.

- [ ] **Step 1: Write the failing system test**

Add to `test/system/gantt_event_markers_test.rb`, inside the `GanttEventMarkersTest` class:

```ruby
  test "the Gantt groups two same-stage events that fall within 16px into one cluster marker" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    stage.update!(start_date: Date.current, end_date: Date.current + 10.days)
    event_type = event_types(:reunion_obra)
    first = Event.create!(project: project, event_type: event_type, title: "Kickoff", event_date: Date.current + 5.days, project_stage: stage)
    second = Event.create!(project: project, event_type: event_type, title: "Revisión", event_date: Date.current + 5.days, project_stage: stage)

    visit new_user_session_path
    fill_in "Correo electrónico", with: users(:juan).email
    fill_in "Contraseña", with: "password123"
    click_button "Iniciar sesión"
    assert_text users(:juan).email

    visit project_path(project)

    assert_selector ".event-marker-group", count: 1, visible: :all
    assert_no_selector ".event-marker-group .event-marker[fill]", visible: :all
    group_fill = evaluate_script("document.querySelector('.event-marker-group .event-marker').getAttribute('fill')")
    assert_equal "#495057", group_fill

    find(".event-marker-group", visible: :all).click
    assert_selector ".list-group-item", text: "Kickoff", visible: :all
    assert_selector ".list-group-item", text: "Revisión", visible: :all

    click_on "Kickoff"
    assert_selector "#edit-event-modal-#{first.id}.show", visible: :all
  end

  test "the Gantt still draws a single plain marker when only one event is at a position" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    stage.update!(start_date: Date.current, end_date: Date.current + 10.days)
    event_type = event_types(:reunion_obra)
    Event.create!(project: project, event_type: event_type, title: "Kickoff", event_date: Date.current + 5.days, project_stage: stage)

    visit new_user_session_path
    fill_in "Correo electrónico", with: users(:juan).email
    fill_in "Contraseña", with: "password123"
    click_button "Iniciar sesión"
    assert_text users(:juan).email

    visit project_path(project)

    assert_selector ".event-marker", count: 1, visible: :all
    assert_no_selector ".event-marker-group", visible: :all
  end
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bin/rails test test/system/gantt_event_markers_test.rb -n "/groups two same-stage/"`
Expected: FAIL — no `.event-marker-group` exists yet (both events currently draw as two independent `.event-marker` diamonds at the same spot).

- [ ] **Step 3: Replace `drawEventMarkers` with a clustering version**

Replace the whole `drawEventMarkers()` method in `app/javascript/controllers/gantt_stage_editor_controller.js` with:

```javascript
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
    this.eventPicker = picker
    this.eventPickerOutsideHandler = (e) => {
      if (!picker.contains(e.target)) this.closeEventPicker()
    }
    setTimeout(() => document.addEventListener("click", this.eventPickerOutsideHandler), 0)
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
  }
```

Note: this replaces the single existing `drawEventMarkers()` method with the version above PLUS four new methods (`drawSingleMarker`, `drawClusterMarker`, `openEventModal`, `openEventPicker`, `closeEventPicker`) — add them all as sibling methods inside the same class, in the same relative position (right after `applyColors()`, before `saveStage()`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/system/gantt_event_markers_test.rb`
Expected: PASS (4 runs: the 2 pre-existing + the 2 new ones — 0 failures)

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/gantt_stage_editor_controller.js test/system/gantt_event_markers_test.rb
git commit -m "Agrupar marcadores de eventos cercanos en el Gantt con un picker al hacer click"
```

---

### Task 2: Warn (non-blocking) when the event's date falls outside its stage's range

**Files:**
- Create: `app/javascript/controllers/event_date_range_warning_controller.js`
- Modify: `app/views/projects/_event_fields.html.erb`
- Create: `test/system/event_date_range_warning_test.rb`

**Interfaces:**
- Consumes: `project.project_stages` (existing, from `_event_fields.html.erb`'s `project:` local).
- Produces: a `data-controller="event-date-range-warning"` wrapper around the stage/date fields in `_event_fields.html.erb`, reusable by both `_add_event_modal.html.erb` and `_edit_event_modals.html.erb` (both already render `_event_fields` — no changes needed there).

- [ ] **Step 1: Write the failing system test**

```ruby
# test/system/event_date_range_warning_test.rb
require "application_system_test_case"

class EventDateRangeWarningTest < ApplicationSystemTestCase
  test "the add-event modal warns, without blocking, when the date falls outside the chosen stage's range" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    stage = project.project_stages.first
    stage.update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 10))

    visit new_user_session_path
    fill_in "Correo electrónico", with: users(:juan).email
    fill_in "Contraseña", with: "password123"
    click_button "Iniciar sesión"
    assert_text users(:juan).email

    visit project_path(project)
    click_button "Evento"

    within "#add-event-modal" do
      select stage.name, from: "Etapa"
      fill_in "Fecha", with: "06/20/2026"
      assert_selector "[data-event-date-range-warning-target='warning']:not([hidden])"
      assert_text "fuera del rango"

      fill_in "Fecha", with: "06/05/2026"
      assert_selector "[data-event-date-range-warning-target='warning'][hidden]", visible: :all
    end
  end

  test "the add-event modal shows no warning when 'Todo el proyecto' is selected" do
    project_type = project_types(:instalaciones)
    project = Project.create!(project_type: project_type, name: "Torre Norte", custom_fields: {})
    project.project_stages.first.update!(start_date: Date.new(2026, 6, 1), end_date: Date.new(2026, 6, 10))

    visit new_user_session_path
    fill_in "Correo electrónico", with: users(:juan).email
    fill_in "Contraseña", with: "password123"
    click_button "Iniciar sesión"
    assert_text users(:juan).email

    visit project_path(project)
    click_button "Evento"

    within "#add-event-modal" do
      select "Todo el proyecto", from: "Etapa"
      fill_in "Fecha", with: "06/20/2026"
      assert_selector "[data-event-date-range-warning-target='warning'][hidden]", visible: :all
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/system/event_date_range_warning_test.rb`
Expected: FAIL — no `data-event-date-range-warning-target` elements exist yet.

- [ ] **Step 3: Write the Stimulus controller**

```javascript
// app/javascript/controllers/event_date_range_warning_controller.js
import { Controller } from "@hotwired/stimulus"

// Non-blocking hint on the shared event form (_event_fields.html.erb): if the
// chosen stage has both dates set and the event's date falls outside them,
// show a warning - the record can still be saved either way.
export default class extends Controller {
  static targets = ["stageSelect", "dateInput", "warning", "warningText"]
  static values = { ranges: Object }

  connect() {
    this.check()
  }

  check() {
    const range = this.rangesValue[this.stageSelectTarget.value]
    const dateValue = this.dateInputTarget.value

    if (!range || !range[0] || !range[1] || !dateValue || (dateValue >= range[0] && dateValue <= range[1])) {
      this.warningTarget.hidden = true
      return
    }

    this.warningTextTarget.textContent =
      `La fecha está fuera del rango de la etapa (${this.formatDate(range[0])} – ${this.formatDate(range[1])}).`
    this.warningTarget.hidden = false
  }

  formatDate(isoDate) {
    const [, month, day] = isoDate.split("-")
    return `${day}/${month}`
  }
}
```

- [ ] **Step 4: Wire the controller into the form**

Modify `app/views/projects/_event_fields.html.erb`. Add this local computation at the very top of the file (before the errors block):

```erb
<%
  stage_date_ranges = project.project_stages.to_h { |stage| [stage.id.to_s, [stage.start_date&.iso8601, stage.end_date&.iso8601]] }
%>
<div data-controller="event-date-range-warning" data-event-date-range-warning-ranges-value="<%= stage_date_ranges.to_json %>">
```

Add the matching closing `</div>` at the very end of the file (after the status field's closing `</div>`).

Change the `project_stage_id` select to add the controller's target/action:
```erb
<div class="mb-3">
  <%= form.label :project_stage_id, "Etapa", class: "form-label" %>
  <%= form.collection_select :project_stage_id, project.project_stages, :id, :name,
        { include_blank: "Todo el proyecto" }, class: "form-select",
        data: { event_date_range_warning_target: "stageSelect", action: "change->event-date-range-warning#check" } %>
</div>
```

Change the `event_date` field to add the controller's target/action, and add the warning element right after its column `<div>`:
```erb
<div class="row g-2 mb-3">
  <div class="col">
    <%= form.label :event_date, "Fecha", class: "form-label" %>
    <%= form.date_field :event_date, class: "form-control",
          data: { event_date_range_warning_target: "dateInput", action: "change->event-date-range-warning#check" } %>
    <div class="text-warning small mt-1" data-event-date-range-warning-target="warning" hidden>
      <i class="bi bi-exclamation-triangle"></i> <span data-event-date-range-warning-target="warningText"></span>
    </div>
  </div>
  <div class="col">
    <%= form.label :event_time, "Hora", class: "form-label" %>
    <%= form.time_field :event_time, class: "form-control" %>
  </div>
</div>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/system/event_date_range_warning_test.rb`
Expected: PASS (2 runs, 0 failures)

- [ ] **Step 6: Run the full event-related test files to check for regressions**

Run: `bin/rails test test/system/gantt_event_markers_test.rb test/system/gantt_color_persistence_test.rb test/controllers/projects_controller_test.rb test/controllers/events_controller_test.rb`
Expected: PASS, same pre-existing baseline failure count as before this task (0 new failures)

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/event_date_range_warning_controller.js app/views/projects/_event_fields.html.erb test/system/event_date_range_warning_test.rb
git commit -m "Avisar (sin bloquear) cuando la fecha de un evento cae fuera del rango de su etapa"
```

---

## Self-Review Notes

- **Spec coverage:** clustering-by-pixel-proximity with gray count marker and click-to-pick (Task 1); non-blocking date-range warning reusing the shared `_event_fields.html.erb` for both add and edit modals, no model/backend change (Task 2). Both items from the spec are covered.
- **Type/interface consistency:** Task 1's new methods (`drawSingleMarker`, `drawClusterMarker`, `openEventModal`, `openEventPicker`, `closeEventPicker`) are all called only from within the same class and from each other — no cross-task naming to double check. Task 2's controller name (`event-date-range-warning`) matches its Stimulus identifier convention (`event_date_range_warning_controller.js` → `event-date-range-warning` per Stimulus's file-to-identifier convention already used by every other controller in this codebase, e.g. `gantt_stage_editor_controller.js` → `gantt-stage-editor`).
- **No placeholders:** every step has complete, runnable code.
