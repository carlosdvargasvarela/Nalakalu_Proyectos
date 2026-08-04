import { Controller } from "@hotwired/stimulus"

// Filters the individual-project access table as the admin types.
export default class extends Controller {
  static targets = ["row"]

  filter(event) {
    const term = event.target.value.toLowerCase()
    this.rowTargets.forEach((row) => {
      row.hidden = !row.dataset.name.includes(term)
    })
  }
}
