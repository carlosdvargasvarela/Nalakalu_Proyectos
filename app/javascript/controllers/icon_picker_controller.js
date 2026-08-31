import { Controller } from "@hotwired/stimulus"

// Lets the user pick an icon from a fixed set of buttons, or type any
// Bootstrap Icons class name directly into the text input.
export default class extends Controller {
  static targets = ["input", "option", "preview"]

  connect() {
    this.refresh()
  }

  pick(event) {
    this.inputTarget.value = event.params.icon
    this.refresh()
  }

  refresh() {
    const current = this.inputTarget.value
    this.optionTargets.forEach((option) => {
      option.classList.toggle("active", option.dataset.iconPickerIconParam === current)
    })
    this.previewTarget.className = `bi ${current}`
  }
}
