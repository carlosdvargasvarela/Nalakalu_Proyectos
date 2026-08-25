import { Controller } from "@hotwired/stimulus"

// Tracks how many project rows are checked for the bulk-assign form, keeping
// the "select all" checkbox, the count badge, and the submit button in sync.
// Also highlights, per row, the existing assignment matching the chosen
// responsible type (typeSelect), and warns before overwriting one.
export default class extends Controller {
  static targets = ["selectAll", "checkbox", "count", "submit", "typeSelect", "row", "search"]

  connect() {
    this.updateCount()
    this.highlightType()
  }

  // Client-side filter over the rows already on the page (one page's worth of
  // projects, so no need for a server round-trip) - matches anywhere in the name.
  filterRows() {
    const query = this.searchTarget.value.trim().toLowerCase()
    this.rowTargets.forEach((row) => {
      row.hidden = query !== "" && !row.dataset.projectName.toLowerCase().includes(query)
    })
  }

  toggleAll() {
    const checked = this.selectAllTarget.checked
    this.checkboxTargets.forEach((cb) => { cb.checked = checked })
    this.updateCount()
  }

  // Non-admin/gerente users see the project list with no checkboxes or bulk-assign
  // form - this controller still connects (it also owns nothing else on the page),
  // so every action here is a no-op when those targets aren't rendered.
  updateCount() {
    if (!this.hasCountTarget || !this.hasSubmitTarget) return
    const count = this.checkboxTargets.filter((cb) => cb.checked).length
    this.countTarget.textContent = `${count} ${count === 1 ? "seleccionado" : "seleccionados"}`
    this.submitTarget.disabled = count === 0
  }

  // Bolds each row's existing-assignment entry that matches the type currently
  // picked in the bulk-assign modal, mirroring the server-side bold applied by
  // the page's own responsible_type_id filter.
  highlightType() {
    if (!this.hasTypeSelectTarget) return
    const typeId = this.typeSelectTarget.value
    this.rowTargets.forEach((row) => {
      row.querySelectorAll("[data-responsible-type-id]").forEach((entry) => {
        entry.classList.toggle("fw-bold", typeId !== "" && entry.dataset.responsibleTypeId === typeId)
      })
    })
  }

  // Projects already assigned to someone for the chosen type get silently
  // overwritten by the server (it replaces the project-wide assignment for
  // that type) - confirm with the user first instead of surprising them.
  confirmOverwrite(event) {
    if (!this.hasTypeSelectTarget) return
    const typeId = this.typeSelectTarget.value
    if (!typeId) return

    const overwrites = this.rowTargets
      .filter((row) => row.querySelector("[data-bulk-select-target='checkbox']:checked"))
      .map((row) => {
        const existing = JSON.parse(row.dataset.existingResponsibles || "{}")
        return existing[typeId] ? `${row.dataset.projectName} (tenía: ${existing[typeId]})` : null
      })
      .filter(Boolean)

    if (overwrites.length === 0) return
    const message = `Se va a reemplazar el responsable actual en ${overwrites.length} proyecto(s):\n\n${overwrites.join("\n")}\n\n¿Continuar?`
    if (!window.confirm(message)) event.preventDefault()
  }
}
