import { Controller } from "@hotwired/stimulus"

// Fetches a rendered markdown help topic and shows it in the shared #help-modal.
export default class extends Controller {
  static values = { topic: String }

  async open(event) {
    event.preventDefault()
    const modalEl = document.getElementById("help-modal")
    const body = modalEl.querySelector('[data-help-target="body"]')
    body.innerHTML = '<div class="text-center text-muted py-4">Cargando…</div>'
    bootstrap.Modal.getOrCreateInstance(modalEl).show()

    const response = await fetch(`/help/${this.topicValue}`)
    body.innerHTML = (response.ok && !response.redirected)
      ? await response.text()
      : '<p class="text-danger">No se encontró este tutorial.</p>'
  }
}
