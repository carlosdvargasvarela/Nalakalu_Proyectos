import { Controller } from "@hotwired/stimulus"

// Lets an admin drag list items to reorder them, persisting the new order via PATCH.
// Reused for both the field-definitions list and the stage-templates list.
export default class extends Controller {
  static values = { url: String }

  start(event) {
    if (!event.target.classList.contains("drag-handle")) return
    this.dragging = event.target.closest("li")
    this.dragging.classList.add("opacity-50")
  }

  end() {
    if (this.dragging) this.dragging.classList.remove("opacity-50")
  }

  over(event) {
    event.preventDefault()
    if (!this.dragging) return
    const target = event.target.closest("li")
    if (!target || target === this.dragging) return
    const rect = target.getBoundingClientRect()
    const after = (event.clientY - rect.top) > rect.height / 2
    this.element.insertBefore(this.dragging, after ? target.nextSibling : target)
  }

  drop(event) {
    event.preventDefault()
    if (!this.dragging) return
    const ids = Array.from(this.element.querySelectorAll("li[data-id]")).map((li) => li.dataset.id)
    this.dragging = null
    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ ids })
    })
  }
}
