import { Controller } from "@hotwired/stimulus"

// Auto-fills a stage row's end date from its start date + a typed duration in days.
export default class extends Controller {
  syncEndDate(event) {
    const row = event.target.closest("tr")
    const startInput = row.querySelector("input[name*='[start_date]']")
    const endInput = row.querySelector("input[name*='[end_date]']")
    if (!startInput || !endInput) return

    const days = parseInt(event.target.value, 10)
    if (!startInput.value || isNaN(days)) return
    const start = new Date(startInput.value + "T00:00:00")
    start.setDate(start.getDate() + days)
    endInput.value = start.toISOString().slice(0, 10)
  }
}
