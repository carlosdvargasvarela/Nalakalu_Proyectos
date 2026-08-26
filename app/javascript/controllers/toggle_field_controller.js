import { Controller } from "@hotwired/stimulus"

// Shows/hides each "field" target depending on whether the "control" select's
// value is in that target's comma-separated data-toggle-field-show-when.
export default class extends Controller {
  static targets = ["control", "field"]

  connect() {
    this.apply()
  }

  apply() {
    const value = this.controlTarget.value
    this.fieldTargets.forEach((field) => {
      field.hidden = !field.dataset.toggleFieldShowWhen.split(",").includes(value)
    })
  }
}
