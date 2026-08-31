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
