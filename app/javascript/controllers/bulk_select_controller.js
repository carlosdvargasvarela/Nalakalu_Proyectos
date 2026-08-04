import { Controller } from "@hotwired/stimulus"

// Tracks how many project rows are checked for the bulk-assign form, keeping
// the "select all" checkbox, the count badge, and the submit button in sync.
export default class extends Controller {
  static targets = ["selectAll", "checkbox", "count", "submit"]

  connect() {
    this.updateCount()
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
}
