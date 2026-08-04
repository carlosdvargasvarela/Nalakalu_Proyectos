import { Controller } from "@hotwired/stimulus"

// Blocks file/image attachments in the bitácora's Trix editor - entries are text-only.
export default class extends Controller {
  connect() {
    this.element.addEventListener("trix-file-accept", this.reject)
  }

  disconnect() {
    this.element.removeEventListener("trix-file-accept", this.reject)
  }

  reject(event) {
    event.preventDefault()
  }
}
