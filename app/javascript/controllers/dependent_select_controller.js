import { Controller } from "@hotwired/stimulus"

// Repopulates a TomSelect-enhanced "select" target with the options relevant
// to whatever's chosen in one or more "control" selects, driven by a
// server-provided { key: [[value, text], ...] } map. Each control contributes
// its data-key (if the selected <option> has one) or its own value; with
// multiple controls the key is their values joined with "_", in DOM order.
export default class extends Controller {
  static targets = ["control", "select"]
  static values = { options: Object }

  connect() {
    if (!this.selectTarget.tomselect) new TomSelect(this.selectTarget, { create: false, allowEmptyOption: true })
    this.apply()
  }

  apply() {
    const key = this.controlTargets.map(control => {
      const selectedOption = control.selectedOptions[0]
      return (selectedOption && selectedOption.dataset.key) || control.value
    }).join("_")
    const ts = this.selectTarget.tomselect
    ts.clear(true)
    ts.clearOptions()
    ;(this.optionsValue[key] || []).forEach(([value, text]) => ts.addOption({ value: String(value), text }))
    ts.refreshOptions(false)
  }
}
